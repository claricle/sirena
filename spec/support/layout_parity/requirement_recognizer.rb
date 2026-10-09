# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Logical requirement and element nodes shared by both SVG producers.
    class RequirementRecognizer
      SIRENA_REQUIREMENT = /\Arequirement-(.+)\z/
      SIRENA_ELEMENT = /\Aelement-(.+)\z/

      def container_kinds
        []
      end

      def elements(extractor, doc)
        doc.xpath("//g[@id]").filter_map do |group|
          kind, key = identify(extractor, group)
          next unless kind

          box = extractor.bbox(group)
          next unless box

          Element.new(kind: kind, key: key, bbox: box,
                      label: extractor.label(group))
        end
      end

      private

      def identify(extractor, group)
        id = group["id"]
        return [:requirement, id[SIRENA_REQUIREMENT, 1]] if id.match?(SIRENA_REQUIREMENT)
        return [:element, id[SIRENA_ELEMENT, 1]] if id.match?(SIRENA_ELEMENT)
        return unless group["class"].to_s.split.include?("node")

        reference_kind(extractor.label(group), id)
      end

      def reference_kind(label, id)
        return [:requirement, id] if label.include?("<<Requirement>>")
        return [:element, id] if label.include?("<<Element>>")
      end
    end
  end
end
