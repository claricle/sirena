# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Treemap branches and leaves keyed by labels; containment supplies parents.
    class TreemapRecognizer
      def container_kinds
        [:treemap_branch]
      end

      def elements(extractor, doc)
        return reference_elements(extractor, doc) if reference?(doc)

        candidate_elements(extractor, doc)
      end

      private

      def reference?(doc)
        nodes_with_class(doc, "treemapContainer").any?
      end

      def reference_elements(extractor, doc)
        branches = nodes_with_class(doc, "treemapSection").filter_map do |node|
          reference_element(extractor, node, "treemapSectionLabel",
                            :treemap_branch)
        end
        leaves = nodes_with_class(doc, "treemapLeafGroup").filter_map do |node|
          reference_element(extractor, node, "treemapLabel", :treemap_leaf)
        end
        branches + leaves
      end

      def reference_element(extractor, node, label_class, kind)
        label_node = nodes_with_class(node, label_class, tag: "text").first
        element(extractor, node, label_node, kind)
      end

      def candidate_elements(extractor, doc)
        branches = doc.xpath("//g[rect and text and g]").filter_map do |node|
          element(extractor, node, node.xpath("./text").first,
                  :treemap_branch)
        end
        leaves = doc.xpath("//g[rect and text and not(g)]").filter_map do |node|
          element(extractor, node, node.xpath("./text").first, :treemap_leaf)
        end
        branches + leaves
      end

      def element(extractor, node, label_node, kind)
        return unless label_node

        label = normalized(label_node)
        box = extractor.bbox(node)
        return unless box && !label.empty?

        Element.new(kind: kind, key: label, bbox: box,
                    label: label, identity: :label)
      end

      def nodes_with_class(node, class_name, tag: "*")
        matcher = "contains(concat(' ', @class, ' '), ' #{class_name} ')"
        node.xpath(".//#{tag}[#{matcher}]")
      end

      def normalized(text)
        text.text.gsub(/\s+/, " ").strip
      end
    end
  end
end
