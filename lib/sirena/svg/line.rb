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

      xml do
        root 'line'
        map_attribute 'id', to: :id
        map_attribute 'class', to: :class_name
        map_attribute 'x1', to: :x1
        map_attribute 'y1', to: :y1
        map_attribute 'x2', to: :x2
        map_attribute 'y2', to: :y2
        map_attribute 'stroke', to: :stroke
        map_attribute 'stroke-width', to: :stroke_width
        map_attribute 'stroke-dasharray', to: :stroke_dasharray
        map_attribute 'transform', to: :transform
        map_attribute 'opacity', to: :opacity
        map_attribute 'fill-opacity', to: :fill_opacity
        map_attribute 'stroke-opacity', to: :stroke_opacity
      end
    end
  end
end
