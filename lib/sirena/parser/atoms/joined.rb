# frozen_string_literal: true

require "parslet"

module Sirena
  module Parser
    module Atoms
      # Matches `inner` and returns everything it consumed as ONE slice.
      # Parslet joins a repetition of plain slices with `Slice#+`, which
      # copies the whole string built so far on every step: a body of
      # n short lines costs O(n^2). Here the pieces are appended to one
      # buffer instead. `inner` must not capture (`.as`): a named result has
      # no text to join, so it raises rather than return a shorter string.
      class Joined < Parslet::Atoms::Base
        def initialize(inner)
          super()
          @inner = inner
        end

        def try(source, context, consume_all)
          anchor = source.consume(0)
          success, value = @inner.apply(source, context, consume_all)
          return [success, value] unless success

          buffer = +""
          append(value, buffer)
          succ(Parslet::Slice.new(anchor.position, buffer, anchor.line_cache))
        end

        def to_s_inner(prec)
          @inner.to_s(prec)
        end

        private

        def append(value, buffer)
          case value
          when Array then value.each { |piece| append(piece, buffer) }
          when Parslet::Slice, String then buffer << value.to_s
          when Hash
            raise ArgumentError, "cannot join a captured #{value.class}"
          end
        end
      end
    end
  end
end
