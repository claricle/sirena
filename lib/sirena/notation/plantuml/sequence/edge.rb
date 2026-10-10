# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # The missing end of a message with no participant there: `[->` and
        # `->]` run to the edge of the diagram, `?->` and `->?` run a label's
        # length from the participant they are written beside.
        class Edge
          # Room between the participant and the end of such an arrow, on top
          # of the label.
          RUN_PADDING = 24.0
          # A ring at the edge sits this far inside it.
          RING_INSET = 8.0

          TOKENS = { "[" => false, "]" => false, "?" => true }.freeze
          private_constant :TOKENS

          attr_reader :side

          # @param token [String] `[`, `]` or `?` as written
          # @param side [Symbol] :left or :right, by position in the line
          # @return [Edge, nil] nil for a token that is not an edge
          def self.read(token, side)
            return unless TOKENS.key?(token)

            new(side: side, local: TOKENS.fetch(token))
          end

          def initialize(side:, local:)
            @side = side
            @local = local
            freeze
          end

          # Measured from the participant instead of from the diagram edge.
          def local?
            @local
          end

          def global?
            !@local
          end

          def left?
            side == :left
          end
        end
      end
    end
  end
end
