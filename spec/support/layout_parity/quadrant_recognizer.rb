# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Quadrant regions and data points keyed by their visible labels.
    class QuadrantRecognizer
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
          element(extractor, node, extractor.label(node), :quadrant_point)
        end
        region_elements + points
      end

      def candidate_elements(extractor, doc)
        labels = doc.xpath("//text[@font-size='14.0' and @font-weight]")
        regions = doc.xpath("//rect").zip(labels).filter_map do |rect, label|
          element(extractor, rect, normalized(label), :quadrant_region)
        end
        point_nodes = doc.xpath("//circle[starts-with(@id, 'point_')]")
        points = point_nodes.filter_map do |circle|
          label = circle.next_element
          element(extractor, circle, normalized(label), :quadrant_point)
        end
        regions + points
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
