# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Sequence participants (contract section 1). Mermaid draws each twice:
    # rect[name] with class actor-top or actor-bottom. Sirena draws one
    # g id="participant-<id>" with no class, read as participant-top.
    class SequenceRecognizer
      def container_kinds
        []
      end

      def elements(extractor, doc)
        reference(extractor, doc) + sirena(extractor, doc)
      end

      private

      def reference(extractor, doc)
        doc.xpath("//rect[@name]").filter_map do |rect|
          position = (rect["class"].to_s.split & %w[actor-top actor-bottom]).first
          next unless position

          Element.new(kind: :"participant-#{position.delete_prefix('actor-')}", key: rect["name"],
                      bbox: extractor.bbox(rect), label: rect["name"])
        end
      end

      def sirena(extractor, doc)
        doc.xpath("//g[starts-with(@id, 'participant-')]").filter_map do |g|
          box = extractor.bbox(g)
          next unless box

          Element.new(kind: :"participant-top", key: g["id"].delete_prefix("participant-"),
                      bbox: box, label: extractor.label(g))
        end
      end
    end
  end
end
