# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Style
        # The look PlantUML 1.2026.6 gives an unstyled diagram, measured from
        # its SVG: the layer every skinparam, `<style>` and element colour
        # is laid over.
        module Defaults
          BOX = { background: "#F1F1F1", border: "#181818",
                  font_colour: "#000000", line_thickness: 0.5,
                  round_corner: 12.5 }.freeze

          RULES = {
            any: { font_name: "sans-serif", font_size: 14,
                   font_colour: "#000000", background: "#F1F1F1",
                   border: "#181818", line_thickness: 0.5 },
            document: { background: "#FFFFFF" },
            state: BOX,
            class: BOX.merge(round_corner: 2.5),
            activity: BOX.merge(font_size: 12),
            note: { background: "#FEFFDD", border: "#181818",
                    line_thickness: 0.5 },
            arrow: { border: "#181818", font_colour: "#000000",
                     line_thickness: 1 },
            start: { background: "#222222", border: "#222222" },
          }.freeze
        end
      end
    end
  end
end
