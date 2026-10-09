# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Block compounds and leaves, with ordinal fallback for anonymous compounds.
    class BlockRecognizer
      def container_kinds
        [:block_container]
      end

      def elements(extractor, doc)
        containers(extractor, doc) + leaves(extractor, doc)
      end

      private

      def containers(extractor, doc)
        compound_nodes(doc).each_with_index.filter_map do |node, index|
          box = extractor.bbox(node, exclude: ["label"])
          next unless box

          Element.new(kind: :block_container,
                      key: "compound-#{index + 1}", bbox: box,
                      identity: :label)
        end
      end

      def leaves(extractor, doc)
        leaf_nodes(doc).filter_map do |node|
          label = extractor.label(node)
          box = extractor.bbox(node, exclude: ["label"])
          next unless box && !label.empty?

          key = semantic_key(node) || label
          identity = semantic_key(node) ? :id : :label
          Element.new(kind: :block_leaf, key: key, bbox: box,
                      label: label, identity: identity)
        end
      end

      def compound_nodes(doc)
        reference = nodes_with_class(doc, "composite", tag: "rect")
        if reference.any?
          return reference.map { |rect| rect.ancestors("g").first }
        end

        doc.xpath("//g[starts-with(@id, 'block-compound-')]")
      end

      def leaf_nodes(doc)
        reference = nodes_with_class(doc, "node", tag: "g")
        return reference.reject { |node| composite?(node) } if reference.any?

        prefix = "starts-with(@id, 'block-')"
        noncompound = "not(contains(@id, 'compound'))"
        doc.xpath("//g[#{prefix} and #{noncompound}]")
      end

      def composite?(node)
        nodes_with_class(node, "composite", tag: "rect").any?
      end

      def semantic_key(node)
        id = node["id"].to_s
        return id.delete_prefix("block-") if id.start_with?("block-")

        id unless id.empty?
      end

      def nodes_with_class(node, class_name, tag: "*")
        matcher = "contains(concat(' ', @class, ' '), ' #{class_name} ')"
        node.xpath(".//#{tag}[#{matcher}]")
      end
    end
  end
end
