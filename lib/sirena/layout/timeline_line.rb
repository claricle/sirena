# frozen_string_literal: true

require "lutaml/model"

module Sirena
  module Layout
    # A straight timeline line with an arrowhead at its far end.
    class TimelineLine < Lutaml::Model::Serializable
      attribute :x1, :float
      attribute :y1, :float
      attribute :x2, :float
      attribute :y2, :float
      attribute :stroke_width, :float
      attribute :dashed, :boolean, default: -> { false }

      # Moves the line by the given offsets.
      def shift(delta_x, delta_y)
        self.x1 += delta_x
        self.x2 += delta_x
        self.y1 += delta_y
        self.y2 += delta_y
      end
    end
  end
end
