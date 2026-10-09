# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Flowchart elements for both sides (contract section 1):
    #   reference: g.node id="flowchart-<id>-<n>", g.cluster id="<id>"
    #   Sirena:    g id="node-<id>",               g id="cluster-<id>"
    # The label group (reference g.label, g.cluster-label) is excluded from a
    # bbox: mermaid draws an attribute-less placeholder rect in it.
    class FlowchartRecognizer
      LABEL_CLASSES = %w[label cluster-label].freeze

      def container_kinds
        [:cluster]
      end

      def elements(extractor, doc)
        doc.xpath("//g[@id]").filter_map do |g|
          kind, key = identify(g)
          next unless kind

          box = extractor.bbox(g, exclude: LABEL_CLASSES)
          Element.new(kind: kind, key: key, bbox: box, label: extractor.label(g)) if box
        end
      end

      private

      def identify(group)
        id = group["id"]
        classes = group["class"].to_s.split
        if classes.include?("node") && (m = id.match(/\Aflowchart-(.+)-\d+\z/))
          [:node, m[1]]
        elsif classes.include?("cluster")
          [:cluster, id]
        elsif (m = id.match(/\Anode-(.+)\z/))
          [:node, m[1]]
        elsif (m = id.match(/\Acluster-(.+)\z/))
          [:cluster, m[1]]
        end
      end
    end
  end
end
