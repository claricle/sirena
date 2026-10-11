# frozen_string_literal: true

require "lutaml/model"
require_relative "timeline_rounding"

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
        settle
      end

      # Rounds the end points to the published precision.
      def settle
        self.x1, self.x2, self.y1, self.y2 =
          [x1, x2, y1, y2].map { |value| TimelineRounding.tidy(value) }
      end
    end
  end
end
