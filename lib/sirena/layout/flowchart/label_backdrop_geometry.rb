# frozen_string_literal: true

module Sirena
  module Layout
    class Flowchart < Base
      # Measured bounds behind an edge label's alphabetic baseline.
      # Paint belongs to the renderer; these coordinates belong to the Scene.
      class LabelBackdropGeometry < Lutaml::Model::Serializable
        attribute :x, :float
        attribute :y, :float
        attribute :width, :float
        attribute :height, :float

        class << self
          def for_label(label, font_size:)
            measured = measured_label(label, font_size)
            new(**bounds(measured))
          end

          private

          # Legacy callers may omit metrics; measure without changing their
          # label or selecting a typography default inside the geometry layer.
          def measured_label(label, font_size)
            size = measured_size(label, font_size)
            label.dup.tap do |measured|
              measured.font_size = font_size
              measured.width = size[:width]
              measured.height = size[:height]
            end
          end

          def measured_size(label, font_size)
            TextMeasurement.measure(
              label.text,
              font_size: font_size,
              width: label.width,
              height: label.height,
            )
          end

          def bounds(label)
            padding = label.font_size / 8.0
            { x: label.x - (label.width / 2.0) - padding,
              y: top(label) - padding,
              **padded_size(label, padding) }
          end

          def padded_size(label, padding)
            { width: label.width + (padding * 2),
              height: label.height + (padding * 2) }
          end

          def top(label)
            label.y - (label.height / 2.0) -
              (Flowchart::MIDDLE_BASELINE_EMS * label.font_size)
          end
        end
      end
    end
  end
end
