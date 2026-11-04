# frozen_string_literal: true

require_relative "box"

module Sirena
  module Notation
    module PlantUMLSalt
      # One thing the renderer draws: a `:rect`, an `:ellipse` (inscribed in
      # the box), a `:polygon` (its `points`), a `:line` (from the box's
      # top-left to its bottom-right) or a `:text` (at the box's left edge,
      # on the baseline `top`). `fill` is a shape's CSS paint; `ink`, when
      # set, is the colour of its outline or line, `weight` its width and
      # `radius` a rectangle's corner.
      class Mark
        attr_reader :kind, :box, :run, :fill, :ink, :weight, :radius, :points

        def initialize(kind, box, run: nil, points: nil, **look)
          @kind = kind
          @box = box
          @run = run
          @points = points
          @fill = look.fetch(:fill, "none")
          @ink = look[:ink]
          @weight = look.fetch(:weight, 1.0)
          @radius = look[:radius]
          freeze
        end
      end
    end
  end
end
