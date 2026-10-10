# frozen_string_literal: true

require "parslet"
require_relative "greedy_run"

module Sirena
  module Parser
    module Atoms
      # Matches `delimiter` once, then one-or-more repetitions of (a run
      # of `segment_class`, then `delimiter` again) -- e.g. Mermaid's ER
      # `~T~` core, `~(?:[^~<terminator>]*~)+`. JS's `.*` is greedy, so
      # this matches through to the LAST delimiter reachable, not the
      # first. Accumulate segments with `<<`, never `.repeat`/`Slice#+`
      # (O(n^2)); call `GreedyRun.scan` per segment. Every call restarts
      # its doubling probe at the small initial size, so a short segment
      # costs about its own length -- that reset is what keeps the whole
      # match linear.
      class DelimitedRun < Parslet::Atoms::Base
        def initialize(delimiter, segment_class)
          super()
          if delimiter.length != 1
            message = "delimiter must be one character, got "
            message += delimiter.inspect
            raise ArgumentError, message
          end

          @delimiter = delimiter
          @segment_re = GreedyRun.anchored(segment_class)
        end

        def try(source, context, _consume_all)
          start = source.bytepos
          anchor = source.consume(0)
          return opening_error(source, context, start) unless opening?(source)

          buffer, segments = consume_segments(source)
          return segment_error(source, context, start) if segments.zero?

          succ(Parslet::Slice.new(anchor.position, buffer, anchor.line_cache))
        end

        def opening?(source)
          source.consume(1).to_s == @delimiter
        end

        def opening_error(source, context, start)
          source.bytepos = start
          context.err(self, source, "Expected #{@delimiter.inspect}")
        end

        def consume_segments(source)
          buffer = +@delimiter
          segments = 0
          while (run = consume_segment(source))
            buffer << run << @delimiter
            segments += 1
          end
          [buffer, segments]
        end

        def consume_segment(source)
          before = source.bytepos
          run = GreedyRun.scan(source, @segment_re)
          return run if source.consume(1).to_s == @delimiter

          source.bytepos = before
          nil
        end

        def segment_error(source, context, start)
          source.bytepos = start
          message = "Expected at least one #{@delimiter.inspect}-closed run"
          context.err(self, source, message)
        end

        def to_s_inner(_prec)
          "#{@delimiter}(?:#{@segment_re.inspect}#{@delimiter})+"
        end
      end
    end
  end
end
