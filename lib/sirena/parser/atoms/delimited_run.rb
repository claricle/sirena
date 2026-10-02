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
          raise ArgumentError, "delimiter must be one character, got #{delimiter.inspect}" if delimiter.length != 1

          @delimiter = delimiter
          @segment_re = GreedyRun.anchored(segment_class)
        end

        def try(source, context, _consume_all)
          start = source.bytepos
          anchor = source.consume(0)
          opening = source.consume(1)

          if opening.to_s != @delimiter
            source.bytepos = start
            return context.err(self, source, "Expected #{@delimiter.inspect}")
          end

          buffer = +opening.to_s
          segments = 0

          loop do
            before = source.bytepos
            run = GreedyRun.scan(source, @segment_re)
            closing = source.consume(1)

            unless closing.to_s == @delimiter
              source.bytepos = before
              break
            end

            buffer << run << @delimiter
            segments += 1
          end

          if segments.zero?
            source.bytepos = start
            return context.err(self, source, "Expected at least one #{@delimiter.inspect}-closed run")
          end

          succ(Parslet::Slice.new(anchor.position, buffer, anchor.line_cache))
        end

        def to_s_inner(_prec)
          "#{@delimiter}(?:#{@segment_re.inspect}#{@delimiter})+"
        end
      end
    end
  end
end
