# frozen_string_literal: true

require 'lutaml/model'
require_relative 'element'

module Sirena
  module Svg
    # SVG Polygon element <polygon>
    #
    # Represents a closed shape defined by a series of points.
    class Polygon < Element
      attribute :points, :string

      writes_attributes :points

      # Helper to build points string from coordinates array
      #
      # @param coords [Array<Array>] Array of [x, y] coordinates
      # @return [String] Points string for polygon
      def self.build_points(coords)
        coords.map { |x, y| "#{x},#{y}" }.join(' ')
      end
    end
  end
end
