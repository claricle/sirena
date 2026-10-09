# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Architecture groups, services, and edges keyed by author semantic ids.
    class ArchitectureRecognizer
      def container_kinds
        [:architecture_group]
      end

      def elements(extractor, doc)
        groups(extractor, doc) +
          services(extractor, doc) +
          edges(extractor, doc)
      end

      private

      def groups(extractor, doc)
        nodes = doc.xpath("//*[@id and starts-with(@id, 'group-')]")
        nodes.filter_map do |node|
          semantic_element(extractor, node, :architecture_group, "group-")
        end
      end

      def services(extractor, doc)
        doc.xpath("//g[starts-with(@id, 'service-')]").filter_map do |node|
          semantic_element(extractor, node, :architecture_service, "service-")
        end
      end

      def edges(extractor, doc)
        edge_nodes(doc).filter_map do |node|
          key = edge_key(node["id"])
          box = extractor.bbox(node)
          Element.new(kind: :architecture_edge, key: key, bbox: box) if box
        end
      end

      def edge_nodes(doc)
        reference = doc.xpath("//path[starts-with(@id, 'L_')]")
        return reference if reference.any?

        doc.xpath("//g[starts-with(@id, 'edge-')]")
      end

      def edge_key(id)
        return id.delete_prefix("edge-") if id.start_with?("edge-")

        id.delete_prefix("L_").sub(/_\d+\z/, "").tr("_", "-")
      end

      def semantic_element(extractor, node, kind, prefix)
        box = extractor.bbox(node, exclude: ["background"])
        return unless box

        key = node["id"].delete_prefix(prefix)
        label = normalized(node.xpath(".//text").last)
        Element.new(kind: kind, key: key, bbox: box, label: label)
      end

      def normalized(text)
        return unless text

        text.text.gsub(/\s+/, " ").strip
      end
    end
  end
end
