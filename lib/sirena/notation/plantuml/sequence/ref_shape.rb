# frozen_string_literal: true

require_relative "fragment_shape"
require_relative "scene"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # The frame of a `ref over` line: the box over the named lifelines,
        # the `ref` tab in its corner and the text centred beneath it.
        class RefShape
          SIDE_PAD = 14.0
          TEXT_PAD = 9.0
          HEIGHT = 44.0
          LABEL_BASELINE = 34.0

          # @param span [Array<Float>] centres of the outermost lifelines
          def self.width_for(label, measure)
            measure.call(label) + (2 * TEXT_PAD)
          end

          attr_reader :x, :width

          def initialize(ref, top, span, measure)
            @ref = ref
            @top = top
            @measure = measure
            @width = [span.last - span.first + (2 * SIDE_PAD),
                      self.class.width_for(ref.label, measure)].max
            @x = ((span.first + span.last) / 2) - (@width / 2)
          end

          def scene
            Scene::Fragment.new(
              x: @x, y: @top, width: @width, height: HEIGHT,
              tab_path: FragmentShape.tab_outline(@x, @top, tab_width),
              separators: [], texts: texts
            )
          end

          private

          def tab_width
            @measure.call("ref") + (2 * FragmentShape::TAB_PAD)
          end

          def texts
            [text("ref", @x + FragmentShape::TAB_PAD, @top + 14,
                  "fragment_tab", "start"),
             text(@ref.label, @x + (@width / 2), @top + LABEL_BASELINE,
                  "fragment_guard", "middle")]
          end

          def text(content, at_x, at_y, role, anchor)
            PlantUML::Scene::Text.new(content: content, x: at_x, y: at_y,
                                      role: role, anchor: anchor)
          end
        end
      end
    end
  end
end
