# frozen_string_literal: true

module Sirena
  module Parser
    module Atoms
      # Matches a run of characters excluded by `char_class` (e.g. `'[^)]'`)
      # in ONE native regex scan, avoiding Parslet's default
      # `match(char_class).repeat(1)` (applies its atom once per character -
      # DoS shape on a long `::icon(...)`/`:::...` body).
      #
      # Consumes CHARACTER-count chunks and matches each with Ruby's own
      # (character-correct) `Regexp`, never `Parslet::Source#matches?`
      # (returns the match length in BYTES; `Source#consume(n)` takes a
      # CHARACTER count - mixing the two over-consumes on a multibyte body,
      # e.g. `root[café]`).
      class GreedyRun < Parslet::Atoms::Base
        # `Parslet::Source#consume(n)` builds a `/(.|$){n}/` regexp to pull
        # n characters at once, and Ruby's regexp engine refuses a repeat
        # count above 100_000 (`RegexpError: too big number for repeat
        # range`). A run longer than this chunk size is consumed in several
        # calls instead of one, well under that ceiling, so an attacker
        # cannot turn a still-huge (but realistic) body into a crash.
        CONSUME_CHUNK = 50_000

        def initialize(char_class)
          super()
          @char_class = char_class
          @anchored = Regexp.new("\\A(?:#{char_class})*", Regexp::MULTILINE)
        end

        # Consumes chunk by chunk (character counts, never byte counts) and
        # joins the parts ONCE at the end. A prior version rebuilt the
        # accumulated `Parslet::Slice` on every chunk via `Slice#+`, which
        # concatenates strings (`str + other.to_s`) - a full copy of
        # everything consumed so far, on every chunk. That made an
        # attacker-sized body (many chunks) quadratic again, just with a
        # divisor of CONSUME_CHUNK instead of 1.
        def try(source, context, _consume_all)
          parts = []
          start_slice = nil

          loop do
            remaining = source.chars_left
            break if remaining.zero?

            chunk = source.consume([remaining, CONSUME_CHUNK].min)
            start_slice ||= chunk
            chunk_str = chunk.to_s
            matched = @anchored.match(chunk_str)[0]
            parts << matched

            if matched.bytesize < chunk_str.bytesize
              source.bytepos -= chunk_str.bytesize - matched.bytesize
              break
            end
          end

          total = parts.join
          return context.err(self, source, 'Expected at least one matching character') if total.empty?

          succ(Parslet::Slice.new(start_slice.position, total, start_slice.line_cache))
        end

        def to_s_inner(_prec)
          @anchored.inspect
        end
      end
    end
  end
end
