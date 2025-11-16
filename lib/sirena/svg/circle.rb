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

      xml do
        root 'circle'
        map_attribute 'id', to: :id
        map_attribute 'class', to: :class_name
        map_attribute 'cx', to: :cx
        map_attribute 'cy', to: :cy
        map_attribute 'r', to: :r
        map_attribute 'fill', to: :fill
        map_attribute 'stroke', to: :stroke
        map_attribute 'stroke-width', to: :stroke_width
        map_attribute 'transform', to: :transform
        map_attribute 'opacity', to: :opacity
      end

      protected

      def element_attributes
        attrs = []
        attrs << %( cx="#{cx}") if cx
        attrs << %( cy="#{cy}") if cy
        attrs << %( r="#{r}") if r
        attrs
      end
    end
  end
end
