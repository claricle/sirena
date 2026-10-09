# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Logical ER entity nodes shared by mmdc references and Sirena renders.
    class ErDiagramRecognizer
      REFERENCE_NODE = /\Aentity-(.+)-\d+\z/
      SIRENA_NODE = /\Aentity-(.+)\z/

      def container_kinds
        []
      end

      def elements(extractor, doc)
        doc.xpath("//g[@id]").filter_map do |group|
          key = key_for(group)
          next unless key

          box = extractor.bbox(group)
          next unless box

          Element.new(kind: :entity, key: key, bbox: box,
                      label: extractor.label(group))
        end
      end

      private

      def key_for(group)
        id = group["id"]
        return id[REFERENCE_NODE, 1] if reference_node?(group)

        id[SIRENA_NODE, 1]
      end

      def reference_node?(group)
        group["class"].to_s.split.include?("node")
      end
    end
  end
end
