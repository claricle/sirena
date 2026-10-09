# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Logical class nodes shared by mmdc references and Sirena renders.
    class ClassDiagramRecognizer
      REFERENCE_NODE = /\AclassId-(.+)-\d+\z/
      SIRENA_NODE = /\Aclass-(.+)\z/

      def container_kinds
        []
      end

      def elements(extractor, doc)
        doc.xpath("//g[@id]").filter_map do |group|
          key = key_for(group["id"])
          next unless key

          box = extractor.bbox(group)
          next unless box

          Element.new(kind: :class, key: key, bbox: box,
                      label: extractor.label(group))
        end
      end

      private

      def key_for(id)
        id[REFERENCE_NODE, 1] || id[SIRENA_NODE, 1]
      end
    end
  end
end
