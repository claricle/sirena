# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Quadrant regions and data points keyed by their visible labels.
    class QuadrantRecognizer
      # A point belongs to the region containing its center, even when its
      # marker straddles the region boundary.
      class PointElement < Element
        def initialize(parent:, **attributes)
          @semantic_parent = parent
          super(**attributes)
        end

        def with_parent(_parent)
          super(@semantic_parent)
        end
      end
      private_constant :PointElement

      def container_kinds
        [:quadrant_region]
      end

      def elements(extractor, doc)
        regions = nodes_with_class(doc, "quadrant")
        return reference_elements(extractor, doc, regions) if regions.any?

        candidate_elements(extractor, doc)
      end

      private

      def reference_elements(extractor, doc, regions)
        region_elements = regions.filter_map do |node|
          element(extractor, node, extractor.label(node), :quadrant_region)
        end
        points = nodes_with_class(doc, "data-point").filter_map do |node|
          point_element(extractor, node, extractor.label(node), region_elements)
        end
        region_elements + points
      end

      def candidate_elements(extractor, doc)
        labels = doc.xpath("//text[number(@font-size) = 14 and @font-weight]")
        regions = doc.xpath("//rect").zip(labels).filter_map do |rect, label|
          element(extractor, rect, normalized(label), :quadrant_region)
        end
        point_nodes = doc.xpath("//circle[starts-with(@id, 'point_')]")
        points = point_nodes.filter_map do |circle|
          label = circle.next_element
          point_element(extractor, circle, normalized(label), regions)
        end
        regions + points
      end

      def point_element(extractor, node, label, regions)
        box = extractor.bbox(node)
        return unless box && !label.empty?

        anchor = Bbox.from_points([box.center])
        parent = regions.find { |region| region.bbox.contain?(anchor) }&.key
        PointElement.new(kind: :quadrant_point, key: label, bbox: box,
                         label: label, identity: :label, parent: parent)
      end

      def element(extractor, node, label, kind)
        box = extractor.bbox(node)
        return unless box && !label.empty?

        Element.new(kind: kind, key: label, bbox: box,
                    label: label, identity: :label)
      end

      def nodes_with_class(node, class_name)
        matcher = "contains(concat(' ', @class, ' '), ' #{class_name} ')"
        node.xpath("//g[#{matcher}]")
      end

      def normalized(text)
        return "" unless text

        text.text.gsub(/\s+/, " ").strip
      end
    end
  end
end
