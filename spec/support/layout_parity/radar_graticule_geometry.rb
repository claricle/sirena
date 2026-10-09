# frozen_string_literal: true

require "nokogiri"

module SpecSupport
  module LayoutParity
    # Extracts and compares radar graticule radii in increasing radius order.
    class RadarGraticuleGeometry
      Comparison = Data.define(:reference_radius, :sirena_radius, :error)

      def self.extract(svg)
        document = Nokogiri::XML(svg) { |config| config.strict.nonet }
        document.remove_namespaces!
        document.xpath("//circle").select { |circle| graticule?(circle) }
          .map { |circle| new(circle).radius }.sort
      end

      def self.compare(reference:, sirena:)
        reference_radii = extract(reference)
        sirena_radii = extract(sirena)
        unless reference_radii.size == sirena_radii.size
          raise ArgumentError, "graticule counts differ"
        end

        reference_radii.zip(sirena_radii).map do |expected, actual|
          Comparison.new(reference_radius: expected, sirena_radius: actual,
                         error: analog_error(actual, expected))
        end
      end

      def self.graticule?(circle)
        circle["class"].to_s.split.include?("radarGraticule") ||
          circle["fill"] == "none"
      end
      private_class_method :graticule?

      def self.analog_error(actual, reference)
        return 0.0 if actual.zero? && reference.zero?
        return Float::INFINITY if reference.zero?

        ((actual / reference) - 1).abs
      end
      private_class_method :analog_error

      def initialize(circle)
        @circle = circle
      end

      def radius
        center, edge = circle_points.map { |point| transform.apply(*point) }
        Math.hypot(edge[0] - center[0], edge[1] - center[1])
      end

      private

      def number(attribute)
        @circle[attribute].to_s[Matrix::NUMBER].to_f
      end

      def circle_points
        center = [number("cx"), number("cy")]
        [center, [center[0] + number("r"), center[1]]]
      end

      def transform
        ancestors = @circle.ancestors.reverse
        @transform ||= ancestors.reduce(Matrix.identity) do |ctm, node|
          ctm * Matrix.parse(node["transform"])
        end * Matrix.parse(@circle["transform"])
      end
    end
  end
end
