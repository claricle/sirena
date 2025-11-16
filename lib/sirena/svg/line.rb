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
      end

      protected

      # Hook for element-specific attributes
      #
      # @return [Array<String>] array of attribute strings
      def element_attributes
        attrs = []
        attrs << %( x1="#{x1}") if x1
        attrs << %( y1="#{y1}") if y1
        attrs << %( x2="#{x2}") if x2
        attrs << %( y2="#{y2}") if y2
        attrs << %( stroke-dasharray="#{stroke_dasharray}") if stroke_dasharray
        attrs
      end
    end
  end
end
