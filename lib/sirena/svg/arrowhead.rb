# frozen_string_literal: true

require_relative 'escaping'
require_relative 'numbers'
require_relative 'path_geometry'
require_relative 'polygon'

module Sirena
  module Svg
    # Draws the arrowheads a path asks for.
    #
    # SVG Tiny 1.2 — the table the svg_conform :metanorma profile enforces —
    # lets a `<marker>` be defined inside `<defs>` and gives no way to
    # reference one: `marker-end` is not an allowed attribute on any element.
    # So a marker request is honoured by drawing the arrowhead instead.
    #
    # Nothing was drawn before this either. Every path carried
    # `marker-end="url(#arrowhead)"` and no document ever defined
    # `#arrowhead`, so every arrow in Sirena's output pointed at nothing and
    # rendered as a plain line.
    #
    # Sirena has one marker and it is an arrowhead, so the reference is read
    # as "put an arrowhead here" rather than looked up.
    class Arrowhead
      # Both measured in stroke widths, so an arrowhead stays in proportion
      # to the line it ends.
      LENGTH = 4.0
      HALF_WIDTH = 2.0

      # An unset stroke-width paints a 1-unit line, per SVG.
      DEFAULT_STROKE_WIDTH = 1.0

      # Arrowheads have no outline of their own, so they take the line's
      # colour. Black matches the stroke a path paints when it names none.
      DEFAULT_COLOR = '#000000'

      # @param path [Svg::Path] the path to draw arrowheads for
      # @return [Array<Svg::Polygon>] one per marker the path asked for
      def self.for(path)
        new(path).polygons
      end

      def initialize(path)
        @path = path
        @geometry = PathGeometry.new(path.d)
      end

      # @return [Array<Svg::Polygon>] the arrowheads, in document order
      def polygons
        [end_arrow, start_arrow].compact
      end

      private

      attr_reader :path, :geometry

      def end_arrow
        return nil if Escaping.blank?(path.marker_end)

        triangle(geometry.terminus)
      end

      # A start marker points back down the path, away from where it goes.
      def start_arrow
        return nil if Escaping.blank?(path.marker_start)

        triangle(reversed(geometry.origin))
      end

      def reversed(anchor)
        anchor && PathGeometry::Anchor.new(anchor.x, anchor.y,
                                           -anchor.dx, -anchor.dy)
      end

      # @param anchor [PathGeometry::Anchor, nil] tip and heading
      # @return [Svg::Polygon, nil] nil when the path gave no heading to
      #   point the arrowhead along
      def triangle(anchor)
        return nil if anchor.nil?

        Polygon.new.tap do |polygon|
          polygon.points = Polygon.build_points(corners(anchor))
          polygon.fill = color
          polygon.fill_opacity = path.stroke_opacity unless Escaping.blank?(path.stroke_opacity)
          polygon.opacity = path.opacity unless Escaping.blank?(path.opacity)
          polygon.transform = path.transform unless Escaping.blank?(path.transform)
        end
      end

      # Tip on the path's end, base one arrow-length back along the heading,
      # squared off either side of it.
      def corners(anchor)
        length = LENGTH * stroke_width
        half = HALF_WIDTH * stroke_width
        base_x = anchor.x - (anchor.dx * length)
        base_y = anchor.y - (anchor.dy * length)

        [[number(anchor.x), number(anchor.y)],
         [number(base_x - (anchor.dy * half)), number(base_y + (anchor.dx * half))],
         [number(base_x + (anchor.dy * half)), number(base_y - (anchor.dx * half))]]
      end

      def number(value)
        Numbers.write(value)
      end

      def stroke_width
        Numbers.read(path.stroke_width) || DEFAULT_STROKE_WIDTH
      end

      def color
        Escaping.blank?(path.stroke) ? DEFAULT_COLOR : path.stroke
      end
    end
  end
end
