# frozen_string_literal: true

require_relative "relation_path_points"
require_relative "segment_box"

module Sirena
  module Notation
    module PlantUML
      # Keeps relation labels from printing over one another, and off other
      # relations' lines. Each label sits on the middle of its own relation,
      # so two relations between the same pair of classes would draw their
      # labels at one point; a later label that meets an earlier one, or
      # another relation's line, slides along its own relation and steps up
      # and down in whole lines until it finds free space.
      class RelationLabelSeparator
        ROLE = "relation_label"
        MARGIN = 1.0
        MAX_STEPS = 24
        SLIDES = [0.0, 0.1, -0.1, 0.2, -0.2, 0.3, -0.3, 0.4, -0.4].freeze

        # @param size [Float] label font size
        # @param width_of [#call] maps label text to its width in the layout
        # @param drawn_width_of [#call] maps label text to the width it is
        #   drawn at, which decides what lines run through it
        def initialize(size:, width_of:, drawn_width_of: width_of)
          @size = size
          @width_of = width_of
          @drawn_width_of = drawn_width_of
        end

        # Moves colliding labels in place.
        # @param scenes [Array<Scene::Relation>]
        # @return [Array<Scene::Relation>] the same scenes
        def call(scenes)
          taken = []
          scenes.each do |scene|
            next unless scene.respond_to?(:texts)

            track = Track.new(scene, scenes)
            scene.texts.each do |text|
              taken << free_box(text, taken, track) if text.role == ROLE
            end
          end
          scenes
        end

        private

        # A relation's own points, and with them the lines of all the others.
        Track = Struct.new(:scene, :scenes) do
          def own
            @own ||= RelationPathPoints.call(
              scene.respond_to?(:path) ? scene.path : nil,
            )
          end

          def lines
            @lines ||= [[own, 0.0], *others_lines]
          end

          private

          def others_lines
            scenes.reject { |other| other.equal?(scene) }
              .select { |other| other.respond_to?(:path) }
              .map { |other| line_of(other) }
          end

          def line_of(other)
            [RelationPathPoints.call(other.path), other.stroke_width.to_f / 2]
          end
        end
        private_constant :Track

        def free_box(text, taken, track)
          home = [text.x, text.y]
          moves(track.own).each do |move|
            shift(text, home, move)
            box = box_of(text)
            return box if free?(text, box, taken, track)
          end
          shift(text, home, [0.0, 0.0])
          box_of(text)
        end

        def shift(text, home, move)
          text.x, text.y = home.zip(move).map(&:sum)
        end

        # Where to try the label, nearest its home first: each step up and
        # down off it, then the same further along the line either way.
        def moves(points)
          return offsets.map { |down| [0.0, down] } if points.size < 2

          SLIDES.flat_map { |slide| slid(points, slide) }
        end

        def slid(points, slide)
          home = RelationPathPoints.along(points, 0.5)
          at = RelationPathPoints.along(points, 0.5 + slide)
          stepped(at[0] - home[0], at[1] - home[1])
        end

        def stepped(across, down)
          offsets.map { |step| [across, down + step] }
        end

        def free?(text, box, taken, track)
          drawn = box_of(text, @drawn_width_of)
          taken.none? { |other| overlap?(box, other) } &&
            track.lines.none? { |line| crossed?(drawn, *line) }
        end

        def crossed?(box, points, half)
          padded = box.zip([-half, -half, half, half]).map(&:sum)
          points.each_cons(2).any? do |from, to|
            SegmentBox.crosses?(padded, from, to)
          end
        end

        def offsets
          [0.0, *(1..MAX_STEPS).flat_map do |step|
            [step * line, -step * line]
          end]
        end

        def line
          @size * 1.3
        end

        def box_of(text, measure = @width_of)
          width = measure.call(text.content)
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
