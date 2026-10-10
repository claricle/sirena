# frozen_string_literal: true

require_relative "keyword_defaults"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # A `note`, `hnote` or `rnote`. `side` is :left, :right, :over or
        # :across. `targets` are participant ids; empty for :across and for a
        # left/right note that hangs off the message before it. `parallel` is
        # true when the note began with `&`. `fill` is a {Fill}, or nil for
        # the default note colour.
        class Note
          EXTRAS = { parallel: false, fill: nil }.freeze
          private_constant :EXTRAS

          attr_reader :shape, :side, :targets, :text, :fill

          def initialize(shape:, side:, targets:, text:, **extras)
            extras = KeywordDefaults.resolve(extras, EXTRAS)
            @shape = shape
            @side = side
            @targets = targets.freeze
            @text = text
            @parallel = extras[:parallel]
            @fill = extras[:fill]
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
