# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # The paint PlantUML 1.2026.6 gives an unstyled sequence diagram,
        # measured from its SVG. It stands in for the default theme only; any
        # other theme keeps painting from its own colour roles.
        module Skin
          PAINT = {
            head_fill: "#E2E2F0", line: "#181818", note_fill: "#FEFFDD",
            bar_fill: "#FFFFFF", tab_fill: "#EEEEEE", box_fill: "#DDDDDD",
            frame_stroke: "#000000", label_fill: "#EEEEEE"
          }.freeze
          WIDTH = {
            thin: "0.5", arrow: "1", frame: "1.5", bar: "1", separator: "1"
          }.freeze
          SIZES = { "message_label" => "13", "note" => "13", "box" => "13",
                    "fragment_tab" => "13", "fragment_guard" => "11",
                    "divider" => "13", "delay" => "11" }.freeze
          HEAD_CORNER = 2.5
          SEPARATOR_DASH = "2,2"
          FAMILY = "sans-serif"
          private_constant :PAINT, :WIDTH, :SIZES, :HEAD_CORNER,
                           :SEPARATOR_DASH, :FAMILY

          private

          # @return [String, nil] what a skinparam set for the role, which
          #   wins over the skin and the theme
          def painted(role)
            @painted[role]
          end

          def read_painted(scene)
            @painted = scene.paint.to_h do |pair|
              role, value = pair.split("=", 2)
              [role.to_sym, value]
            end
          end

          def skinned?
            theme.nil? || theme.name.nil? || theme.name == "default"
          end

          # @return [String, nil] the skin colour for the role, or nil when a
          #   theme paints it
          def skin_paint(role)
            PAINT.fetch(role) if skinned?
          end

          def skin_width(role)
            WIDTH.fetch(role) if skinned?
          end

          def skin_corner(shape_corner)
            skinned? ? HEAD_CORNER : shape_corner
          end

          def skin_size(role)
            SIZES[role] if skinned?
          end

          def skin_family
            FAMILY if skinned?
          end

          def skin_dash(default)
            skinned? ? SEPARATOR_DASH : default
          end
        end
      end
    end
  end
end
