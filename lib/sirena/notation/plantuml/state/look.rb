# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module State
        # The measures of PlantUML 1.2026.6's state drawing, read from its
        # SVG, and the curve a transition is drawn as.
        module Look
          TEXT_FONT = 14.0
          TEXT_LINE = 16.49
          TEXT_PAD = 6.0
          LEAF_BAR = 26.49
          BAR = 22.0
          EMPTY_BODY = 23.51
          NOTE_FONT = 13.0
          NOTE_LINE = 15.31
          NOTE_PAD_X = 6.0
          NOTE_PAD_RIGHT = 15.0
          NOTE_PAD_Y = 5.0
          CANVAS_MARGIN = 20.0
          FOLD = 10.0
          TAIL = 4.0
          HISTORY_SIZE = { width: 22.0, height: 22.0 }.freeze
          TERMINAL_RADIUS = { "start" => 10.0, "end" => 11.0 }.freeze

          # @return [Hash] a start or end marker's width and height
          def self.terminal(kind)
            size = TERMINAL_RADIUS.fetch(kind) * 2
            { width: size, height: size }
          end
        end
      end
    end
  end
end
