# frozen_string_literal: true

require 'lutaml/model'
require_relative 'arrowhead'
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

      # Four renderers set `marker-end`; `marker-start` is settable directly
      # too. Neither is emitted — Svg::Arrowhead draws them instead. See
      # that class for why.
      writes_attributes :d, :stroke_dasharray, :stroke_linecap, :stroke_linejoin

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

      # The arrowheads this path asked for, drawn beside it.
      #
      # A head is a sibling shape rather than a child because `<path>` takes
      # no drawable children. Each is a Polygon — a leaf that draws no
      # siblings of its own — so one head is always one entry.
      #
      # @return [Array<String>] one entry of markup per arrowhead
      def sibling_markup
        Arrowhead.for(self).map(&:to_xml)
      end
    end
  end
end
