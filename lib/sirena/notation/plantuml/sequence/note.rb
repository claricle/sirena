# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # A `note`, `hnote` or `rnote`. `side` is :left, :right, :over or
        # :across. `targets` are participant ids; empty for :across and for a
        # left/right note that hangs off the message before it. `parallel` is
        # true when the note began with `&`.
        class Note
          attr_reader :shape, :side, :targets, :text

          def initialize(shape:, side:, targets:, text:, parallel: false)
            @shape = shape
            @side = side
            @targets = targets.freeze
            @text = text
            @parallel = parallel
            freeze
          end

          def parallel?
            @parallel
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
