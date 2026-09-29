# frozen_string_literal: true

require "parslet"

module Sirena
  module Parser
    module Atoms
      # Matches a run of `char_class` (e.g. `'[^)]'`) in bounded native
      # regex scans, avoiding Parslet's default `match(char_class).repeat`
      # (applies its atom once per character -- DoS shape on a long run).
      #
      # Consumes CHARACTER-count chunks and matches each with Ruby's own
      # (character-correct) `Regexp`, never `Parslet::Source#matches?`
      # (returns the match length in BYTES; `Source#consume(n)` takes a
      # CHARACTER count - mixing the two over-consumes on a multibyte body,
      # e.g. `root[café]`).
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
          start_slice = source.consume(0)
          matched = self.class.scan(source, @anchored)

          if @min.positive? && matched.empty?
            return context.err(self, source, 'Expected at least one matching character')
          end

          succ(Parslet::Slice.new(start_slice.position, matched, start_slice.line_cache))
        end

        # The `\A(?:class)*` regexp that `scan` expects, for a Parslet-style
        # character class string such as `'[^~\n]'`.
        def self.anchored(char_class)
          Regexp.new("\\A(?:#{char_class})*", Regexp::MULTILINE)
        end

        # Scans `anchored` (an `\A(?:...)* ` regex) against `source` from
        # its current position, joining the parts ONCE at the end (never
        # per chunk -- that would make an attacker-sized body quadratic
        # again). Shared with `DelimitedRun`, which calls this once per
        # delimited segment with its own segment regex.
        def self.scan(source, anchored)
          buffer = +''
          probe = INITIAL_PROBE

          loop do
            remaining = source.chars_left
            break if remaining.zero?

            chunk_size = [remaining, probe].min
            chunk_str = source.consume(chunk_size).to_s
            # `anchored` can carry a fixed UTF-8 encoding (a char class with
            # a literal `\uXXXX` escape, e.g. JS_WHITESPACE_CHARS); matching
            # it against a chunk in an incompatible encoding (binary input
            # with a high byte) raises for the WHOLE chunk, even when the
            # class would have accepted a leading ASCII run before that
            # byte. Retry on just that run instead of discarding it.
            matched =
              begin
                anchored.match(chunk_str)[0]
              rescue Encoding::CompatibilityError
                anchored.match(ascii_prefix(chunk_str))[0]
              end
            buffer << matched

            if matched.bytesize < chunk_str.bytesize
              source.bytepos -= chunk_str.bytesize - matched.bytesize
              break
            end

            probe = [probe * 2, CHUNK].min
          end

          buffer
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
