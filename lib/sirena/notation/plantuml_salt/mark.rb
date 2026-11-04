# frozen_string_literal: true

require_relative "box"

module Sirena
  module Notation
    module PlantUMLSalt
      # One thing the renderer draws: a `:rect`, a `:line` (from the box's
      # top-left to its bottom-right) or a `:text` (at the box's left edge,
      # on the baseline `top`). `fill` names a rectangle's look.
      class Mark
        attr_reader :kind, :box, :run, :fill

        def initialize(kind, box, run: nil, fill: nil)
          @kind = kind
          @box = box
          @run = run
          @fill = fill
          freeze
        end
      end
    end
  end
end
