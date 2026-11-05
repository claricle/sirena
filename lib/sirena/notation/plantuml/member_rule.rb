# frozen_string_literal: true

require_relative "scene"

module Sirena
  module Notation
    module PlantUML
      # How PlantUML draws the rule of a class body's separator line: `..`
      # dotted, `==` two solid lines two pixels apart, `__` a hairline and
      # `--` a solid line.
      module MemberRule
        extend self

        Style = Struct.new(:width, :dash, :double)
        DOUBLE_GAP = 2.0
        STYLES = {
          "." => Style.new(1.0, "1,2", false),
          "=" => Style.new(1.0, nil, true),
          "_" => Style.new(0.5, nil, false),
          "-" => Style.new(1.0, nil, false),
        }.freeze
        private_constant :DOUBLE_GAP, :STYLES

        # @param character [String] the separator's character: . = _ or -
        # @param pieces [Array<Scene::Segment>] the rule's unstyled parts
        # @return [Array<Scene::Segment>] the parts as drawn
        def style(character, pieces)
          rule = STYLES.fetch(character, STYLES["-"])
          drawn = pieces.map { |piece| styled(piece, rule) }
          rule.double ? drawn + drawn.map { |piece| lowered(piece) } : drawn
        end

        private

        def styled(piece, rule)
          Scene::Segment.new(x1: piece.x1, y1: piece.y1, x2: piece.x2,
                             y2: piece.y2, width: rule.width, dash: rule.dash)
        end

        def lowered(piece)
          Scene::Segment.new(x1: piece.x1, y1: piece.y1 + DOUBLE_GAP,
                             x2: piece.x2, y2: piece.y2 + DOUBLE_GAP,
                             width: piece.width, dash: piece.dash)
        end
      end
    end
  end
end
