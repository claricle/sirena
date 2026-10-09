# frozen_string_literal: true

require "nokogiri"

module SpecSupport
  module LayoutParity
    # Extracts and compares Quadrant point radii by visible point label.
    class QuadrantPointGeometry
      Measurement = Data.define(:key, :radius)
      Comparison = Data.define(:key, :reference_radius, :sirena_radius, :error)

      def self.extract(svg)
        document = Nokogiri::XML(svg) { |config| config.strict.nonet }
        document.remove_namespaces!
        reference_points(document) || sirena_points(document)
      end

      def self.compare(reference:, sirena:)
        reference_points = extract(reference)
        sirena_points = extract(sirena)
        unless reference_points.size == sirena_points.size
          raise ArgumentError, "point counts differ"
        end

        pair(index(reference_points), index(sirena_points))
      end

      def self.reference_points(document)
        groups = document.xpath(
          "//g[contains(concat(' ', @class, ' '), ' data-point ')]",
        )
        return if groups.empty?

        groups.map do |group|
          measurement(group.at_xpath(".//circle"), normalized(group))
        end
      end
      private_class_method :reference_points

      def self.sirena_points(document)
        document.xpath(
          "//circle[starts-with(@id, 'point_') or starts-with(@id, 'point-')]",
        ).map do |circle|
          measurement(circle, normalized(circle.next_element))
        end
      end
      private_class_method :sirena_points

      def self.measurement(circle, key)
        Measurement.new(key: key, radius: new(circle).radius)
      end
      private_class_method :measurement

      def self.normalized(node)
        node.text.gsub(/\s+/, " ").strip
      end
      private_class_method :normalized

      def self.index(points)
        indexed = points.to_h { |point| [point.key, point] }
        return indexed if indexed.size == points.size

        raise ArgumentError, "point labels are not unique"
      end
      private_class_method :index

      def self.pair(reference, sirena)
        unless reference.keys.sort == sirena.keys.sort
          raise ArgumentError, "point labels differ"
        end

        reference.keys.sort.map do |key|
          expected = reference.fetch(key).radius
          actual = sirena.fetch(key).radius
          Comparison.new(key: key, reference_radius: expected,
                         sirena_radius: actual,
                         error: analog_error(actual, expected))
        end
      end
      private_class_method :pair

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

      def circle_points
        center = [number("cx"), number("cy")]
        [center, [center[0] + number("r"), center[1]]]
      end

      def number(attribute)
        @circle[attribute].to_s[Matrix::NUMBER].to_f
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
