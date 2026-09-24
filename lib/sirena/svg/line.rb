# frozen_string_literal: true

require 'lutaml/model'
require_relative 'element'

module Sirena
  module Svg
    # SVG Line element <line>
    #
    # Represents a straight line between two points.
    class Line < Element
      attribute :x1, :float
      attribute :y1, :float
      attribute :x2, :float
      attribute :y2, :float
      attribute :stroke_dasharray, :string

      writes_attributes :x1, :y1, :x2, :y2, :stroke_dasharray
    end
  end
end
