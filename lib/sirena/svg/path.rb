# frozen_string_literal: true

require 'lutaml/model'
require_relative 'element'

module Sirena
  module Svg
    # SVG Path element <path>
    #
    # Represents complex shapes and lines using SVG path data syntax.
    # Commonly used for drawing edges in diagrams with curves and bend points.
    class Path < Element
      attribute :d, :string
      attribute :stroke_dasharray, :string
      attribute :stroke_linecap, :string
      attribute :stroke_linejoin, :string
      attribute :marker_end, :string
      attribute :marker_start, :string

      xml do
        root 'path'
        map_attribute 'id', to: :id
        map_attribute 'class', to: :class_name
        map_attribute 'd', to: :d
        map_attribute 'fill', to: :fill
        map_attribute 'stroke', to: :stroke
        map_attribute 'stroke-width', to: :stroke_width
        map_attribute 'stroke-dasharray', to: :stroke_dasharray
        map_attribute 'stroke-linecap', to: :stroke_linecap
        map_attribute 'stroke-linejoin', to: :stroke_linejoin
        map_attribute 'marker-end', to: :marker_end
        map_attribute 'marker-start', to: :marker_start
        map_attribute 'transform', to: :transform
        map_attribute 'opacity', to: :opacity
      end

      # Helper to build path data from move and line commands
      #
      # @param commands [Array<Hash>] Path commands
      # @return [String] Path data string
      def self.build_path_data(commands)
        commands.map do |cmd|
          case cmd[:type]
          when :move
            "M #{cmd[:x]} #{cmd[:y]}"
          when :line
            "L #{cmd[:x]} #{cmd[:y]}"
          when :curve
            "Q #{cmd[:cx]} #{cmd[:cy]} #{cmd[:x]} #{cmd[:y]}"
          when :bezier
            c1x = cmd[:c1x]
            c1y = cmd[:c1y]
            c2x = cmd[:c2x]
            c2y = cmd[:c2y]
            "C #{c1x} #{c1y} #{c2x} #{c2y} #{cmd[:x]} #{cmd[:y]}"
          when :close
            'Z'
          end
        end.join(' ')
      end

      protected

      def element_attributes
        attrs = []
        attrs << %( d="#{d}") if d
        attrs << %( stroke-dasharray="#{stroke_dasharray}") if stroke_dasharray
        attrs << %( stroke-linecap="#{stroke_linecap}") if stroke_linecap
        attrs << %( stroke-linejoin="#{stroke_linejoin}") if stroke_linejoin
        attrs << %( marker-end="#{marker_end}") if marker_end
        attrs << %( marker-start="#{marker_start}") if marker_start
        attrs
      end
    end
  end
end
