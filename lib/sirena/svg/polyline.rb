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
