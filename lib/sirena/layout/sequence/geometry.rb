# frozen_string_literal: true

module Sirena
  module Layout
    class Sequence < Base
      # Sizes and gaps of mermaid's default sequence config, shifted so
      # the diagram starts at (0, 0) of the view box instead of at
      # (-diagramMarginX, -diagramMarginY).
      module Geometry
        ACTOR_WIDTH = 150
        ACTOR_HEIGHT = 65
        ACTOR_MARGIN = 50
        DIAGRAM_MARGIN_X = 50
        DIAGRAM_MARGIN_Y = 10
        MESSAGE_PITCH = 44
        NOTE_MARGIN = 10
        LIFELINE_TAIL = 20
        CANVAS_TRIM = 1
        # y of the line every row is counted from: the actor box bottom.
        FIRST_ROW = DIAGRAM_MARGIN_Y + ACTOR_HEIGHT
      end
    end
  end
end
