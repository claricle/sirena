# frozen_string_literal: true

require 'lutaml/model'
require_relative 'element'

module Sirena
  module Svg
    # SVG Circle element <circle>
    #
    # Represents a circle shape with center point and radius.
    class Circle < Element
      attribute :cx, :float
      attribute :cy, :float
      attribute :r, :float

      writes_attributes :cx, :cy, :r
    end
  end
end
