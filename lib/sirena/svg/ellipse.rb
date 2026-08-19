# frozen_string_literal: true

require 'lutaml/model'
require_relative 'element'

module Sirena
  module Svg
    # SVG Ellipse element <ellipse>
    #
    # Represents an ellipse shape with center point and radii.
    class Ellipse < Element
      attribute :cx, :float
      attribute :cy, :float
      attribute :rx, :float
      attribute :ry, :float

      # Emitted nothing before this: an Ellipse rendered as `<ellipse fill="red"/>`
      # with no geometry, and renderer/c4.rb:242 draws boundaries with it.
      writes_attributes :cx, :cy, :rx, :ry

      xml do
        root 'ellipse'
        map_attribute 'id', to: :id
        map_attribute 'class', to: :class_name
        map_attribute 'cx', to: :cx
        map_attribute 'cy', to: :cy
        map_attribute 'rx', to: :rx
        map_attribute 'ry', to: :ry
        map_attribute 'fill', to: :fill
        map_attribute 'stroke', to: :stroke
        map_attribute 'stroke-width', to: :stroke_width
        map_attribute 'transform', to: :transform
        map_attribute 'opacity', to: :opacity
      end
    end
  end
end
