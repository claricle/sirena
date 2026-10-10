# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # The sole info/version text, keyed by its fixed contract role.
    class InfoRecognizer
      def container_kinds
        []
      end

      def elements(extractor, doc)
        text = doc.at_xpath("//text")
        return [] unless text

        box = extractor.bbox(text)
        return [] unless box

        element = Element.new(kind: :info_text, key: "info-text", bbox: box,
                              label: normalized(text))
        [element]
      end

      private

      def normalized(text)
        text.text.gsub(/\s+/, " ").strip
      end
    end
  end
end
