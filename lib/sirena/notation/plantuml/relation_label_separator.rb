# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # Keeps relation labels from printing over one another. Each label sits
      # on the middle of its own relation, so two relations between the same
      # pair of classes would draw their labels at one point; a later label
      # that meets an earlier one steps up and down in whole lines until it
      # finds free space.
      class RelationLabelSeparator
        ROLE = "relation_label"
        MARGIN = 1.0
        MAX_STEPS = 24

        # @param size [Float] label font size
        # @param width_of [#call] maps label text to its drawn width
        def initialize(size:, width_of:)
          @size = size
          @width_of = width_of
        end

        # Moves colliding labels in place.
        # @param scenes [Array<Scene::Relation>]
        # @return [Array<Scene::Relation>] the same scenes
        def call(scenes)
          taken = []
          scenes.each do |scene|
            next unless scene.respond_to?(:texts)

            scene.texts.each do |text|
              taken << free_box(text, taken) if text.role == ROLE
            end
          end
          scenes
        end

        private

        def free_box(text, taken)
          home = text.y
          offsets.each do |offset|
            text.y = home + offset
            box = box_of(text)
            return box if taken.none? { |other| overlap?(box, other) }
          end
          text.y = home
          box_of(text)
        end

        def offsets
          [0.0, *(1..MAX_STEPS).flat_map do |step|
            [step * line, -step * line]
          end]
        end

        def line
          @size * 1.3
        end

        def box_of(text)
          width = @width_of.call(text.content)
          left = left_edge(text, width)
          [left - MARGIN, text.y - @size, left + width + MARGIN,
           text.y + (@size / 4)]
        end

        def left_edge(text, width)
          text.anchor == "middle" ? text.x - (width / 2) : text.x
        end

        def overlap?(first, second)
          first[0] < second[2] && second[0] < first[2] &&
            first[1] < second[3] && second[1] < first[3]
        end
      end
    end
  end
end
