# frozen_string_literal: true

require_relative "scene"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # The label of a message under `autonumber`: its number in bold,
        # then the label, four pixels on. The pair is placed as one unit
        # where the plain label would have been.
        class NumberedLabel
          GAP = 4.0

          # @param measure [#call] text width in pixels
          def initialize(measure)
            @measure = measure
          end

          # @return [Float] the width the number adds to the label
          def extra(message)
            return 0.0 unless message.number

            @measure.call(message.number.to_s) + GAP
          end

          # @param anchor [String] where the unit sits at `x`: "start",
          #   "middle" or "end"
          # @return [Array<Scene::Text>] the number, then the label
          def texts(message, x, y, anchor)
            left = left_of(message, x, anchor)
            [piece(message.number.to_s, left, y, "message_number", "bold"),
             piece(message.label, left + extra(message), y, "message_label")]
          end

          private

          def left_of(message, x, anchor)
            total = extra(message) + @measure.call(message.label)
            { "middle" => x - (total / 2), "end" => x - total }.fetch(anchor, x)
          end

          def piece(content, x, y, role, weight = nil)
            PlantUML::Scene::Text.new(content: content, x: x, y: y, role: role,
                                      anchor: "start", weight: weight)
          end
        end
      end
    end
  end
end
