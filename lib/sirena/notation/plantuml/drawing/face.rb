# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Drawing
        # How wide PlantUML's face sets text. The closest advances sirena
        # carries are DejaVu Sans, within about 5% of the JAR's.
        module Face
          # The share of a font size between the middle of a line and its
          # baseline: sirena anchors text by its middle, the JAR by its
          # baseline.
          MIDDLE = 0.3418

          module_function

          # @return [Float]
          def width(text, size:, bold: false)
            TextMeasurement.measure_in(bold ? :dejavu_bold : :dejavu,
                                       text.to_s, font_size: size)[:width]
          end

          # @return [Float] the middle of a line whose baseline is given
          def middle(baseline, size)
            baseline - (MIDDLE * size)
          end
        end
      end
    end
  end
end
