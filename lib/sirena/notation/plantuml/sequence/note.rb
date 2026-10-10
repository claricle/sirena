# frozen_string_literal: true

require_relative "embedded"
require_relative "keyword_defaults"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # A `note`, `hnote` or `rnote`. `side` is :left, :right, :over or
        # :across. `targets` are participant ids; empty for :across and for a
        # left/right note that hangs off the message before it. `parallel` is
        # true when the note began with `&`. `fill` is a {Fill}, or nil for
        # the default note colour. `picture` is the laid-out embedded diagram.
        class Note
          EXTRAS = { parallel: false, fill: nil, picture: nil }.freeze
          private_constant :EXTRAS

          attr_reader :shape, :side, :targets, :text, :fill, :picture

          def initialize(shape:, side:, targets:, text:, **extras)
            extras = KeywordDefaults.resolve(extras, EXTRAS)
            @shape = shape
            @side = side
            @targets = targets.freeze
            @text = text
            @parallel = extras[:parallel]
            @fill = extras[:fill]
            @picture = extras[:picture]
            freeze
          end

          def parallel?
            @parallel
          end

          # PlantUML also reads the two characters `\n` as a line break.
          def lines
            text.split(/\\n|\n/, -1)
          end

          # @return [Embedded, nil] the diagram this note holds
          def embedded
            Embedded.read(text)
          end

          # @param picture [Picture] the embedded diagram, laid out
          # @return [Note] this note with its picture
          def with_picture(picture)
            Note.new(shape: shape, side: side, targets: targets, text: text,
                     parallel: parallel?, fill: fill, picture: picture)
          end

          def attached?
            targets.empty? && %i[left right].include?(side)
          end
        end
      end
    end
  end
end
