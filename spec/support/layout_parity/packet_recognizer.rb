# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Packet fields, keyed by their contained label on both SVG producers.
    class PacketRecognizer
      def container_kinds
        []
      end

      def elements(extractor, doc)
        field_rects(doc).filter_map do |rect|
          field_element(extractor, doc, rect)
        end
      end

      private

      def field_rects(doc)
        matcher = "contains(concat(' ', @class, ' '), ' packetBlock ')"
        reference = doc.xpath("//rect[#{matcher}]")
        reference.empty? ? doc.xpath("//rect") : reference
      end

      def field_element(extractor, doc, rect)
        box = extractor.bbox(rect)
        return unless box

        label = label_for(extractor, doc, box)
        return unless label

        Element.new(kind: :field, key: label, bbox: box, label: label,
                    identity: :label)
      end

      def label_for(extractor, doc, box)
        labels = doc.xpath("//text").filter_map do |text|
          label_entry(extractor, text, box)
        end
        labels.min_by(&:first)&.last
      end

      def label_entry(extractor, text, box)
        anchor = extractor.bbox(text)
        return unless anchor && box.contain?(anchor)

        label = text.text.gsub(/\s+/, " ").strip
        return if label.empty?

        [distance(anchor.center, box.center), label]
      end

      def distance(left, right)
        Math.hypot(left[0] - right[0], left[1] - right[1])
      end
    end
  end
end
