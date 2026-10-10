# frozen_string_literal: true

require_relative "scene"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # The shapes drawn at one end of an arrow, measured against PlantUML.
        # `inward` is +1 or -1: the side of the lifeline the shaft lies on.
        class ArrowMarks
          LENGTH = 10.0
          HALF_WIDTH = 4.0
          CROSS_CENTRE = 11.5
          CROSS_HALF = 5.0
          RING_RADIUS = 4.0
          RING_SHIFT = 5.5
          RING_LIFT = 0.75

          # @return [Array(Array<Scene::Mark>, Float)] the shapes and the x
          #   the shaft stops at
          def self.for(arrow_end, at_x, at_y, inward)
            new(arrow_end, at_x, at_y, inward).build
          end

          def initialize(arrow_end, x_pos, y_pos, inward)
            @end = arrow_end
            @x = x_pos
            @y = y_pos
            @inward = inward
          end

          def build
            marks = []
            shaft = @x
            shaft = glyph_marks(marks) if @end.glyph
            marks << ring if @end.circle
            shaft = @x + (@inward * RING_RADIUS) if ring_alone?
            [marks, shaft]
          end

          private

          def ring_alone?
            @end.circle && @end.glyph.nil?
          end

          def glyph_marks(marks)
            return cross(marks) if @end.glyph == :cross

            tip = @end.circle ? @x + (@inward * RING_SHIFT) : @x
            marks.concat(half_or_head(tip))
            tip
          end

          def half_or_head(tip)
            back = tip + (@inward * LENGTH)
            case @end.glyph
            when :filled, :open then [triangle(tip, back)]
            when :upper then [half(tip, back, -HALF_WIDTH)]
            when :lower then [half(tip, back, HALF_WIDTH)]
            when :upper_open then [stroke([tip, @y], [back, @y - HALF_WIDTH])]
            else [stroke([tip, @y], [back, @y + HALF_WIDTH])]
            end
          end

          def triangle(tip, back)
            polygon([[tip, @y], [back, @y - HALF_WIDTH],
                     [back, @y + HALF_WIDTH]])
          end

          def half(tip, back, side)
            polygon([[tip, @y], [back, @y + side], [back, @y]])
          end

          def cross(marks)
            centre = @x + (@inward * CROSS_CENTRE)
            [-CROSS_HALF, CROSS_HALF].each do |slant|
              marks << stroke([centre - CROSS_HALF, @y - slant],
                              [centre + CROSS_HALF, @y + slant], heavy: true)
            end
            centre
          end

          def polygon(points)
            list = points.map { |px, py| "#{px},#{py}" }.join(" ")
            Scene::Mark.new(kind: "polygon", filled: @end.glyph != :open,
                            points: list)
          end

          def stroke(from, to, heavy: false)
            Scene::Mark.new(kind: "line", x1: from[0], y1: from[1],
                            x2: to[0], y2: to[1], heavy: heavy)
          end

          def ring
            Scene::Mark.new(kind: "circle", cx: @x, cy: @y - RING_LIFT,
                            r: RING_RADIUS)
          end
        end
      end
    end
  end
end
