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
    end
  end
end
