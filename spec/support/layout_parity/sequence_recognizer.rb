# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Sequence participants (contract section 1). Mermaid's top and bottom
    # boxes are presentation copies of one semantic participant, so the top
    # copy supplies its geometry. Sirena draws that participant once.
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
        doc.xpath("//rect[@name]").filter_map do |rect|
          next unless rect["class"].to_s.split.include?(REFERENCE_CLASS)

          Element.new(kind: :"participant-top", key: rect["name"],
                      bbox: extractor.bbox(rect), label: rect["name"])
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
