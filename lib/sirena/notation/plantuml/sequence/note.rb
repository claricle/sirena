# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # A `note`, `hnote` or `rnote`. `side` is :left, :right, :over or
        # :across. `targets` are participant ids; empty for :across and for a
        # left/right note that hangs off the message before it.
        class Note
          attr_reader :shape, :side, :targets, :text

          def initialize(shape:, side:, targets:, text:)
            @shape = shape
            @side = side
            @targets = targets.freeze
            @text = text
            freeze
          end

          # PlantUML also reads the two characters `\n` as a line break.
          def lines
            text.split(/\\n|\n/, -1)
          end

          def attached?
            targets.empty? && %i[left right].include?(side)
          end
        end
      end
    end
  end
end
