# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Error icon and role-keyed text lines on both SVG producers.
    class ErrorRecognizer
      TEXT_ROLES = %w[message version].freeze

      def container_kinds
        []
      end

      def elements(extractor, doc)
        [icon_element(extractor, doc), *text_elements(extractor, doc)].compact
      end

      private

      def icon_element(extractor, doc)
        boxes = icon_nodes(extractor, doc).filter_map do |node|
          extractor.bbox(node)
        end
        box = Bbox.union(boxes) if boxes.any?
        return unless box

        Element.new(kind: :error_icon, key: "error-icon", bbox: box,
                    identity: :label)
      end

      def icon_nodes(extractor, doc)
        reference = nodes_with_class(doc, "error-icon")
        reference.empty? ? sirena_icon_nodes(extractor, doc) : reference
      end

      def sirena_icon_nodes(extractor, doc)
        circles = doc.xpath("//circle")
        outline = circles.max_by { |circle| extractor.bbox(circle)&.area.to_f }
        return [] unless outline

        outline_box = extractor.bbox(outline)
        inset_rects = doc.xpath("//rect").select do |rect|
          box = extractor.bbox(rect)
          box && outline_box.contain?(box)
        end
        circles.to_a + inset_rects
      end

      def text_elements(extractor, doc)
        error_texts(doc).each_with_index.filter_map do |text, index|
          box = extractor.bbox(text)
          next unless box

          role = TEXT_ROLES.fetch(index, "line-#{index + 1}")
          Element.new(kind: :error_text, key: role, bbox: box,
                      label: normalized(text), identity: :label)
        end
      end

      def error_texts(doc)
        reference = nodes_with_class(doc, "error-text", tag: "text")
        reference.empty? ? doc.xpath("//text") : reference
      end

      def nodes_with_class(doc, class_name, tag: "*")
        matcher = "contains(concat(' ', @class, ' '), ' #{class_name} ')"
        doc.xpath("//#{tag}[#{matcher}]")
      end

      def normalized(text)
        text.text.gsub(/\s+/, " ").strip
      end
    end
  end
end
