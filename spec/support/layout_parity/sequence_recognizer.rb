# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Sequence participants (contract section 1). Mermaid's top and bottom
    # boxes are presentation copies of one semantic participant, so the top
    # copy supplies its geometry. Sirena draws that participant once.
    # Mermaid draws a box participant as a top-level rect and an actor,
    # boundary, control or entity participant as a g; both carry the name.
    class SequenceRecognizer
      REFERENCE_CLASS = "actor-top"

      def container_kinds
        []
      end

      def elements(extractor, doc)
        reference(extractor, doc) + sirena(extractor, doc)
      end

      private

      def reference(extractor, doc)
        doc.xpath("//*[(self::rect or self::g)][@name]").filter_map do |node|
          next unless node["class"].to_s.split.include?(REFERENCE_CLASS)

          Element.new(kind: :"participant-top", key: node["name"],
                      bbox: extractor.bbox(node), label: node["name"])
        end
      end

      def sirena(extractor, doc)
        doc.xpath("//g[starts-with(@id, 'participant-')]").filter_map do |g|
          box = extractor.bbox(g)
          next unless box

          key = g["id"].delete_prefix("participant-")
          Element.new(kind: :"participant-top", key: key,
                      bbox: box, label: extractor.label(g))
        end
      end
    end
  end
end
