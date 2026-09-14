# frozen_string_literal: true

require 'lutaml/model'
require_relative 'element'

module Sirena
  module Svg
    # SVG Polyline element <polyline>
    #
    # Represents an open shape defined by a series of connected points.
    class Polyline < Element
      attribute :points, :string

      # Emitted nothing before this: a Polyline rendered as `<polyline stroke="blue"/>`
      # with no points, and renderer/xy_chart.rb:337 draws line series with it.
      writes_attributes :points

      xml do
        root 'polyline'
        map_attribute 'id', to: :id
        map_attribute 'class', to: :class_name
        map_attribute 'points', to: :points
        map_attribute 'fill', to: :fill
        map_attribute 'stroke', to: :stroke
        map_attribute 'stroke-width', to: :stroke_width
        map_attribute 'transform', to: :transform
        map_attribute 'opacity', to: :opacity
        map_attribute 'fill-opacity', to: :fill_opacity
        map_attribute 'stroke-opacity', to: :stroke_opacity
      end

      # Helper to build points string from coordinates array
      #
      # @param coords [Array<Array>] Array of [x, y] coordinates
      # @return [String] Points string for polyline
      def self.build_points(coords)
        coords.map { |x, y| "#{x},#{y}" }.join(' ')
      end
    end
  end
end
