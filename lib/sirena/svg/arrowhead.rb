# frozen_string_literal: true

require_relative "escaping"
require_relative "numbers"
require_relative "path_geometry"
require_relative "polygon"

module Sirena
  module Svg
    # Draws the arrowheads a path asks for.
    #
    # SVG Tiny 1.2 (:metanorma profile) has no way to reference a
    # <marker>, so marker-end="url(#...)" resolves to nothing -- draw
    # the head directly here rather than adding <marker>/<defs> wiring.
    #
    # A head hidden under its node (centre-to-centre edges) is
    # Engine#layout_graph's bug, not this class's.
    class Arrowhead
      # Chosen by eye as stroke-width multiples so the head scales with the
      # line. These are not derived from mermaid-js's marker proportions.
      LENGTH = 4.0
      HALF_WIDTH = 2.0

      # An unset stroke-width paints a 1-unit line, per SVG.
      DEFAULT_STROKE_WIDTH = 1.0

      # SVG's own "no marker here", and its initial `stroke`. A path carrying
      # either is asking for nothing to be drawn, which is not the same as
      # not having asked.
      NONE = "none"
      PAINT_ATTRIBUTES = {
        fill_opacity: :stroke_opacity,
        opacity: :opacity,
        transform: :transform,
      }.freeze
      private_constant :LENGTH, :HALF_WIDTH, :DEFAULT_STROKE_WIDTH, :NONE,
                       :PAINT_ATTRIBUTES

      # @param path [Svg::Path] the path to draw arrowheads for
      # @return [Array<Svg::Polygon>] one per marker the path asked for
      def self.for(path)
        new(path).polygons
      end

      def initialize(path)
        @path = path
      end

      # Reads the path's data at most once, and not at all when no marker was
      # asked for — which is most paths. Nothing is cached on the instance:
      # the path is mutable, so a remembered geometry would answer for a `d`
      # the caller has since replaced.
      #
      # A head the path gave no heading for is dropped rather than returned as
      # nil, so a position in the result names a head only when both were
      # asked for and both could be drawn.
      #
      # @return [Array<Svg::Polygon>] the end-marker head before the
      #   start-marker head, with either absent
      def polygons
        heads = requested_heads
        return [] if heads.empty?

        # An arrowhead is the end of the line, so a line painting nothing
        # ends in nothing. SVG's initial `stroke` is `none`, and inherited
        # paint is not visible from here, so an unstroked path gets no head
        # rather than a black one floating free of it.
        return [] unless painted?

        geometry = PathGeometry.new(path.d)
        heads.filter_map { |head| triangle(anchor_for(head, geometry)) }
      end

      private

      attr_reader :path

      def requested_heads
        markers = [[:end, path.marker_end], [:start, path.marker_start]]
        markers.filter_map do |head, marker|
          head if names_something?(marker)
        end
      end

      def anchor_for(head, geometry)
        return geometry.terminus if head == :end

        reversed(geometry.origin)
      end

      # Asked of a marker and of a stroke alike, because `none` is SVG's own
      # "nothing here" for both. Escaping.blank? catches an unset attribute;
      # an attribute set to `''` or to whitespace is set, and still names
      # nothing.
      #
      # @param value [Object] an attribute value
      # @return [Boolean] whether it names something rather than nothing
      def names_something?(value)
        return false if Escaping.blank?(value)

        named = value.to_s.strip.downcase
        !named.empty? && named != NONE
      end

      # A line paints only if it names a colour AND has a width to paint it
      # with. SVG Tiny 1.2 gives `stroke-width="0"` no stroke at all, so a
      # head there would be the same free-floating triangle an unset stroke
      # would have left.
      #
      # @return [Boolean] whether the path paints a stroke at all
      def painted?
        names_something?(path.stroke) && stroke_width.positive?
      end

      # Unlike marker orient="auto", which points along the path, Sirena
      # deliberately reverses a start head to form a bidirectional arrow. No
      # renderer sets marker_start, so this deviation is reached only by a
      # caller assigning `path.marker_start=` directly -- Path.from_xml no
      # longer exists to reach it either.
      def reversed(anchor)
        anchor && PathGeometry::Anchor.new(anchor.x, anchor.y,
                                           -anchor.dx, -anchor.dy)
      end

      # @param anchor [PathGeometry::Anchor, nil] tip and heading
      # @return [Svg::Polygon, nil] nil when the path gave no heading to
      #   point the arrowhead along or a computed corner is non-finite
      def triangle(anchor)
        return nil if anchor.nil?

        coordinates = corners(anchor)
        return nil unless coordinates.flatten.all?(&:finite?)

        Polygon.new.tap do |polygon|
          set_points(polygon, coordinates)
          copy_paint(polygon)
        end
      end

      def set_points(polygon, coordinates)
        written = coordinates.map do |x, y|
          [Numbers.write(x), Numbers.write(y)]
        end
        polygon.points = Polygon.build_points(written)
      end

      # The head is painted where the line's stroke would have been, so it
      # inherits the line's opacity and sits in its coordinate space.
      def copy_paint(polygon)
        polygon.fill = path.stroke
        PAINT_ATTRIBUTES.each do |target, source|
          value = presence(path.public_send(source))
          polygon.public_send("#{target}=", value)
        end
      end

      # Tip on the path's end, base one arrow-length back along the heading,
      # squared off either side of it.
      def corners(anchor)
        tip = anchor.to_a.first(2)
        base = arrow_base(anchor)
        offset = corner_offset(anchor)
        [tip, subtract(base, offset), add(base, offset)]
      end

      def arrow_base(anchor)
        length = LENGTH * stroke_width
        [anchor.x - (anchor.dx * length),
         anchor.y - (anchor.dy * length)]
      end

      def corner_offset(anchor)
        half = HALF_WIDTH * stroke_width
        [anchor.dy * half, -anchor.dx * half]
      end

      def add(left, right)
        left.zip(right).map(&:sum)
      end

      def subtract(left, right)
        left.zip(right).map { |a, b| a - b }
      end

      # nil rather than lutaml's unset sentinel or an empty attribute value,
      # neither of which should be handed to a new polygon.
      def presence(value)
        value unless Escaping.blank?(value) || value.to_s.strip.empty?
      end

      # Zero remains zero because it suppresses the stroke. Unset,
      # unreadable, non-finite, and negative widths fall back because SVG
      # ignores those error values and uses the inherited or initial width.
      # Non-finite widths are guarded here before multiplication. A finite
      # width can still overflow as the corners are computed, so #triangle
      # rejects that non-finite result instead of writing it into points.
      def stroke_width
        width = Numbers.read(path.stroke_width)
        return DEFAULT_STROKE_WIDTH unless width&.finite? && !width.negative?

        width
      end
    end
  end
end
