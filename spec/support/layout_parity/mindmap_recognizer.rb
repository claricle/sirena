# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Mindmap nodes keyed by their visible semantic labels on both producers.
    class MindmapRecognizer
      NODE_CLASS = "mindmap-node"

      def container_kinds
        []
      end

      def elements(extractor, doc)
        reference = nodes_with_class(doc, NODE_CLASS)
        return reference_elements(extractor, reference) if reference.any?

        candidate_elements(extractor, doc)
      end

      private

      def reference_elements(extractor, nodes)
        nodes.filter_map do |node|
          element(extractor, node, extractor.label(node))
        end
      end

      def candidate_elements(extractor, doc)
        doc.xpath("//rect").filter_map do |rect|
          text = rect.xpath("following-sibling::text[1]").first
          element(extractor, rect, normalized(text)) if text
        end
      end

      def element(extractor, node, label)
        box = extractor.bbox(node)
        return unless box && !label.empty?

        Element.new(kind: :mindmap_node, key: label, bbox: box,
                    label: label, identity: :label)
      end

      def nodes_with_class(doc, class_name)
        matcher = "contains(concat(' ', @class, ' '), ' #{class_name} ')"
        doc.xpath("//g[#{matcher}]")
      end

      def normalized(text)
        text.text.gsub(/\s+/, " ").strip
      end
    end
  end
end
