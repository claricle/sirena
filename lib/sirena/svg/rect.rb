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

      # fill-opacity is NOT listed here. Element already emits it for every
      # element, and listing it again produced
      # `fill-opacity="0.5" fill-opacity="0.5"` — the last 5 malformed cases
      # in the corpus.
      #
      # The attribute declaration and its lutaml mapping below stay, so
      # fill-opacity itself parses and re-emits exactly once. That is NOT the
      # same as a Rect round-tripping in full: the mapping block omits
      # stroke_opacity, which Element declares and emits, so a from_xml Rect
      # leaves that one unset. Harmless, since an unset lutaml attribute is
      # treated as absent, but it is a separate gap and not a claim to make
      # here.
      writes_attributes :x, :y, :width, :height, :rx, :ry, :stroke_dasharray

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
    end
  end
end
