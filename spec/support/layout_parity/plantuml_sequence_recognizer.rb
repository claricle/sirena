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
        found = doc.xpath("//g").filter_map do |group|
          next unless classes(group).include?(REFERENCE_HEAD)

          participant(extractor, group, group["data-qualified-name"])
        end
        return found unless found.empty?

        legacy_reference_participants(extractor, doc)
      end

      # Teoz omits PlantUML's interactive participant wrappers. Its first
      # rectangle/text pair for each lifeline title is still the participant
      # head; label identity lets it match Sirena even when the source used an
      # alias that the legacy SVG did not preserve.
      def legacy_reference_participants(extractor, doc)
        root = legacy_root(doc)
        return [] unless root

        legacy_lifelines(root).filter_map do |group|
          legacy_head(extractor, root, group)
        end
      end

      def legacy_head(extractor, root, group)
        label = group.at_xpath("./title")&.text
        box = legacy_head_bbox(extractor, root, label)
        return unless box

        Element.new(kind: :participant, key: label, bbox: box,
                    label: label, identity: :label)
      end

      def legacy_head_bbox(extractor, root, label)
        text = participant_texts(root, label).min_by { |node| node["y"].to_f }
        shape = text&.previous_element
        extractor.bbox(shape) if shape&.name == "rect"
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
        return legacy_reference_messages(extractor, doc) if groups.empty?

        groups.each_with_index.filter_map do |group, index|
          box = extractor.bbox(group)
          next unless box

          Element.new(kind: :message, key: index + 1, bbox: box,
                      label: normalize(group.xpath(".//text").map(&:text)))
        end
      end

      # The same Teoz output leaves each arrow's primitives and label as a
      # direct run of siblings. A horizontal line distinguishes a message run
      # from participant labels and other unwrapped text.
      def legacy_reference_messages(extractor, doc)
        root = legacy_root(doc)
        return [] unless root

        children = root.element_children
        children.each_with_index.filter_map do |node, index|
          legacy_message(extractor, children, node, index)
        end
      end

      def legacy_message(extractor, children, node, index)
        return unless node.name == "text"

        run = preceding_run(children, index)
        return unless run.any? { |item| horizontal_line?(item) }

        boxes = [*run, node].filter_map { |item| extractor.bbox(item) }
        box = Bbox.union(boxes)
        return unless box

        Element.new(kind: :message, key: index, bbox: box,
                    label: normalize([node.text]), identity: :label)
      end

      def legacy_root(doc)
        doc.at_xpath("/svg/g")
      end

      def legacy_lifelines(root)
        root.xpath("./g").select do |group|
          group.at_xpath("./title") &&
            group.xpath("./line").any? { |line| dashed?(line) }
        end
      end

      def participant_texts(root, label)
        root.xpath("./text").select do |text|
          normalize([text.text]) == normalize([label]) &&
            text.previous_element&.name == "rect"
        end
      end

      def preceding_run(children, index)
        children[0...index].reverse_each.take_while do |node|
          node.name != "text"
        end.reverse
      end

      def horizontal_line?(node)
        node.name == "line" && node["y1"] == node["y2"]
      end

      def dashed?(line)
        line["style"].to_s.include?("stroke-dasharray")
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
