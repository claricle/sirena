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
          box = extractor.bbox(rect)
          next unless box

          label = label_for(extractor, doc, box)
          next unless label

          Element.new(kind: :field, key: label, bbox: box, label: label,
                      identity: :label)
        end
      end

      private

      def field_rects(doc)
        reference = doc.xpath("//rect[contains(concat(' ', @class, ' '), ' packetBlock ')]")
        reference.empty? ? doc.xpath("//rect") : reference
      end

      def label_for(extractor, doc, box)
        labels = doc.xpath("//text").filter_map do |text|
          anchor = extractor.bbox(text)
          next unless anchor && box.contain?(anchor)

          [distance(anchor.center, box.center), text.text.gsub(/\s+/, " ").strip]
        end
        labels.reject { |entry| entry.last.empty? }.min_by(&:first)&.last
      end

      def distance(left, right)
        Math.hypot(left[0] - right[0], left[1] - right[1])
      end
    end
  end
end
