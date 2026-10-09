# frozen_string_literal: true

require "nokogiri"

module SpecSupport
  module LayoutParity
    # Measures circular Git Graph marker radii without treating other marker
    # shapes as circles.
    class GitGraphMarkerGeometry
      Measurement = Data.define(:key, :radius)
      Comparison = Data.define(
        :key, :reference_radius, :sirena_radius, :error
      )

      CENTER_EPSILON = 0.01

      def self.extract(svg)
        document = Nokogiri::XML(svg) { |config| config.strict.nonet }
        document.remove_namespaces!
        reference = reference_nodes(document)
        return sirena_measurements(document) if reference.empty?

        reference_measurements(reference)
      end

      def self.compare(reference:, sirena:)
        unless reference.size == sirena.size
          raise ArgumentError, "marker counts differ"
        end
        unless reference.map(&:key) == sirena.map(&:key)
          raise ArgumentError, "marker keys differ"
        end

        reference.zip(sirena).map { |pair| comparison(*pair) }
      end

      def self.reference_nodes(document)
        document.xpath("//circle | //rect").select do |node|
          node["class"].to_s.split.include?("commit")
        end
      end
      private_class_method :reference_nodes

      def self.reference_measurements(nodes)
        groups(nodes).each_with_index.map do |group, index|
          radii = group.select { |node| node.name == "circle" }
            .map { |circle| new(circle).radius }
          Measurement.new(key: "commit-#{index + 1}", radius: radii.max)
        end
      end
      private_class_method :reference_measurements

      def self.sirena_measurements(document)
        document.xpath("//circle").each_with_index.map do |circle, index|
          Measurement.new(key: "commit-#{index + 1}",
                          radius: new(circle).radius)
        end
      end
      private_class_method :sirena_measurements

      def self.groups(nodes)
        nodes.each_with_object([]) do |node, grouped|
          center = new(node).center
          group = grouped.find do |members|
            same_center?(new(members.first).center, center)
          end
          group ? group << node : grouped << [node]
        end
      end
      private_class_method :groups

      def self.same_center?(left, right)
        Math.hypot(left[0] - right[0], left[1] - right[1]) <= CENTER_EPSILON
      end
      private_class_method :same_center?

      def self.comparison(reference, sirena)
        Comparison.new(key: reference.key,
                       reference_radius: reference.radius,
                       sirena_radius: sirena.radius,
                       error: radius_error(reference, sirena))
      end
      private_class_method :comparison

      def self.radius_error(reference, sirena)
        return unless reference.radius

        analog_error(sirena.radius, reference.radius)
      end
      private_class_method :radius_error

      def self.analog_error(actual, reference)
        return 0.0 if actual.zero? && reference.zero?
        return Float::INFINITY if reference.zero?

        ((actual / reference) - 1).abs
      end
      private_class_method :analog_error

      def initialize(node)
        @node = node
      end

      def center
        transform.apply(*local_center)
      end

      def radius
        center_point = center
        edge = transform.apply(*local_edge)
        distance(center_point, edge)
      end

      private

      def local_center
        return [number("cx"), number("cy")] if @node.name == "circle"

        [number("x") + (number("width") / 2),
         number("y") + (number("height") / 2)]
      end

      def local_edge
        x_pos, y_pos = local_center
        [x_pos + number("r"), y_pos]
      end

      def distance(left, right)
        Math.hypot(right[0] - left[0], right[1] - left[1])
      end

      def number(attribute)
        @node[attribute].to_s[Matrix::NUMBER].to_f
      end

      def transform
        ancestors = @node.ancestors.reverse
        @transform ||= ancestors.reduce(Matrix.identity) do |ctm, node|
          ctm * Matrix.parse(node["transform"])
        end * Matrix.parse(@node["transform"])
      end
    end
  end
end
