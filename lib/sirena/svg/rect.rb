# frozen_string_literal: true

require 'lutaml/model'
require_relative 'element'

module Sirena
  module Svg
    # SVG Rectangle element <rect>
    #
    # Represents a rectangle shape with position, dimensions, and optional
    # rounded corners.
    class Rect < Element
      attribute :x, :float
      attribute :y, :float
      attribute :width, :float
      attribute :height, :float
      attribute :rx, :float
      attribute :ry, :float
      attribute :stroke_dasharray, :string
      attribute :fill_opacity, :string

      xml do
        root 'rect'
        map_attribute 'id', to: :id
        map_attribute 'class', to: :class_name
        map_attribute 'x', to: :x
        map_attribute 'y', to: :y
        map_attribute 'width', to: :width
        map_attribute 'height', to: :height
        map_attribute 'rx', to: :rx
        map_attribute 'ry', to: :ry
        map_attribute 'fill', to: :fill
        map_attribute 'fill-opacity', to: :fill_opacity
        map_attribute 'stroke', to: :stroke
        map_attribute 'stroke-width', to: :stroke_width
        map_attribute 'stroke-dasharray', to: :stroke_dasharray
        map_attribute 'transform', to: :transform
        map_attribute 'opacity', to: :opacity
      end

      protected

      def element_attributes
        attrs = []
        attrs << %( x="#{x}") if x
        attrs << %( y="#{y}") if y
        attrs << %( width="#{width}") if width
        attrs << %( height="#{height}") if height
        attrs << %( rx="#{rx}") if rx
        attrs << %( ry="#{ry}") if ry
        attrs << %( stroke-dasharray="#{stroke_dasharray}") if stroke_dasharray
        attrs << %( fill-opacity="#{fill_opacity}") if fill_opacity
        attrs
      end
    end
  end
end
