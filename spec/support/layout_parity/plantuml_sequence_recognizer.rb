# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Logical sequence participants and messages shared by pinned PlantUML
    # references and Sirena's PlantUML renderer. A participant is drawn as a
    # head and a tail copy by both producers; the head copy supplies its
    # geometry. Messages are keyed by their order in the document.
    class PlantumlSequenceRecognizer
      REFERENCE_HEAD = "participant-head"
      REFERENCE_MESSAGE = "message"
      SIRENA_PARTICIPANT = /\Aparticipant-(?<name>.+)-(?<top>-?[\d.]+)\z/
      SIRENA_MESSAGE = "message-"

      def container_kinds
        []
      end

      def elements(extractor, doc)
        participants(extractor, doc) + messages(extractor, doc)
      end

      private

      def participants(extractor, doc)
        reference_participants(extractor, doc) +
          sirena_participants(extractor, doc)
      end

      def reference_participants(extractor, doc)
        doc.xpath("//g").filter_map do |group|
          next unless classes(group).include?(REFERENCE_HEAD)

          participant(extractor, group, group["data-qualified-name"])
        end
      end

      def sirena_participants(extractor, doc)
        heads = doc.xpath("//g").filter_map do |group|
          found = SIRENA_PARTICIPANT.match(group["id"].to_s)
          [group, found[:name], found[:top].to_f] if found
        end
        topmost(heads).map do |group, name, _top|
          participant(extractor, group, name)
        end
      end

      def topmost(heads)
        heads.group_by { |_group, name, _top| name }.values.map do |copies|
          copies.min_by(&:last)
        end
      end

      def participant(extractor, group, name)
        box = extractor.bbox(group)
        return unless box

        Element.new(kind: :participant, key: name, bbox: box,
                    label: normalize(group.xpath(".//text").map(&:text)))
      end

      def messages(extractor, doc)
        groups = doc.xpath("//g").select { |group| message?(group) }
        groups.each_with_index.filter_map do |group, index|
          box = extractor.bbox(group)
          next unless box

          Element.new(kind: :message, key: index + 1, bbox: box,
                      label: normalize(group.xpath(".//text").map(&:text)))
        end
      end

      def message?(group)
        classes(group).include?(REFERENCE_MESSAGE) ||
          group["id"].to_s.start_with?(SIRENA_MESSAGE)
      end

      def classes(group)
        group["class"].to_s.split
      end

      def normalize(texts)
        texts.join(" ").gsub(/\s+/, " ").strip
      end
    end
  end
end
