# frozen_string_literal: true

require "parslet"

module Sirena
  module Parser
    module Atoms
      # Matches a run of `char_class` (e.g. `[^\]]`) in bounded native
      # regex scans, avoiding Parslet's default `match(char_class).repeat`
      # (applies its atom once per character -- DoS shape on a long run).
      #
      # Consumes CHARACTER-count chunks and matches each with Ruby's own
      # (character-correct) `Regexp`, never `Parslet::Source#matches?`
      # (returns the match length in BYTES; `Source#consume(n)` takes a
      # CHARACTER count - mixing the two over-consumes on a multibyte body,
      # e.g. the text of kanban's `root[café]`).
      class GreedyRun < Parslet::Atoms::Base
        # First chunk size tried; doubles each round up to CHUNK. A short
        # run (the common case) then costs about its own length instead of
        # a fixed CHUNK per call.
        INITIAL_PROBE = 64
        private_constant :INITIAL_PROBE

        # `Parslet::Source#consume(n)` builds a `/(.|$){n}/` regexp to pull
        # n characters at once, and Ruby's regexp engine refuses a repeat
        # count above 100_000 (`RegexpError: too big number for repeat
        # range`). Chunks stay well under that ceiling.
        CHUNK = 50_000
        private_constant :CHUNK

        # `min: 1` (default) requires at least one matching character
        # (`char_class+`); `min: 0` allows an empty match (`char_class*`).
        def initialize(char_class, min: 1)
          super()
          @char_class = char_class
          @min = min
          @anchored = self.class.anchored(char_class)
        end

        def try(source, context, _consume_all)
          origin = source.consume(0)
          matched = self.class.scan(source, @anchored)

          message = "Expected at least one matching character"
          empty = @min.positive? && matched.empty?
          return context.err(self, source, message) if empty

          succ(Parslet::Slice.new(origin.position, matched, origin.line_cache))
        end

        # The `\A(?:class)*` regexp that `scan` expects, for a Parslet-style
        # character class string such as `[^~\n]`.
        def self.anchored(char_class)
          Regexp.new("\\A(?:#{char_class})*", Regexp::MULTILINE)
        end

        # Scans `anchored` (an `\A(?:...)* ` regex) against `source` from
        # its current position, joining the parts ONCE at the end (never
        # per chunk -- that would make an attacker-sized body quadratic
        # again). Shared with `DelimitedRun`, which calls this once per
        # delimited segment with its own segment regex.
        def self.scan(source, anchored)
          buffer = +""
          probe = INITIAL_PROBE

          loop do
            break if source.chars_left.zero?

            matched, complete = scan_chunk(source, anchored, probe)
            buffer << matched
            break unless complete

            probe = [probe * 2, CHUNK].min
          end

          buffer
        end

        # A fixed-UTF-8 regex can reject a binary chunk even when its leading
        # ASCII run matches. Retry against that prefix, then restore any bytes
        # consumed beyond the match.
        def self.scan_chunk(source, anchored, probe)
          size = [source.chars_left, probe].min
          chunk = source.consume(size).to_s
          matched = anchored_match(anchored, chunk)
          excess = chunk.bytesize - matched.bytesize
          source.bytepos -= excess
          [matched, excess.zero?]
        end

        def self.anchored_match(anchored, chunk)
          anchored.match(chunk)[0]
        rescue Encoding::CompatibilityError
          anchored.match(ascii_prefix(chunk))[0]
        end

        # The bytes of `chunk_str` before its first byte >= 0x80, safe to
        # match against a fixed-UTF-8 `anchored` because every one of them
        # is also valid UTF-8. `chunk_str` always carries an ASCII-compatible
        # encoding here: it comes from a `Parslet::Source`, and
        # `Source#initialize` itself already rejects any encoding that
        # isn't (`LineCache#scan_for_line_endings` matching a `US-ASCII`
        # `/\n/` against it) before this method ever runs.
        def self.ascii_prefix(chunk_str)
          high_byte = chunk_str.each_byte.find_index { |byte| byte >= 0x80 }
          high_byte ? chunk_str.byteslice(0, high_byte) : chunk_str
        end
        private_class_method :ascii_prefix

        def to_s_inner(_prec)
          @anchored.inspect
        end
      end
    end
  end
end
