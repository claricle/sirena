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
      # The attribute declaration above stays so `fill_opacity=` is still a
      # settable Ruby accessor -- from_xml no longer works on Rect at all
      # (Lutaml::Model::TypeOnlyMappingError, no `root` declared). It still
      # re-emits through Element exactly once, whichever way it was set.
      writes_attributes :x, :y, :width, :height, :rx, :ry, :stroke_dasharray
    end
  end
end
