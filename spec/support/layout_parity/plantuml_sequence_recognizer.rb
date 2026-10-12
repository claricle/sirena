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
          next if embedded_picture_element?(group)
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
        return extractor.bbox(shape) if shape&.name == "rect"

        legacy_actor_bbox(extractor, text)
      end

      def legacy_actor_bbox(extractor, text)
        ellipse = text&.next_element
        path = ellipse&.next_element
        return unless actor_shape?(ellipse, path)

        Bbox.union([ellipse, path].filter_map { |node| extractor.bbox(node) })
      end

      def actor_shape?(ellipse, path)
        ellipse&.name == "ellipse" && path&.name == "path"
      end

      def sirena_participants(extractor, doc)
        heads = doc.xpath("//g").filter_map do |group|
          next if embedded_picture_element?(group)

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
        groups = message_groups(doc)
        return legacy_reference_messages(extractor, doc) if groups.empty?

        groups.each_with_index.filter_map do |group, index|
          recognized_message(extractor, group, index)
        end
      end

      def message_groups(doc)
        doc.xpath("//g").select do |group|
          message?(group) && !embedded_picture_element?(group)
        end
      end

      def recognized_message(extractor, group, index)
        box = extractor.bbox(group)
        return unless box

        Element.new(kind: :message, key: index + 1, bbox: box,
                    label: normalize(group.xpath(".//text").map(&:text)))
      end

      # The same Teoz output leaves each arrow's primitives and label as a
      # direct run of siblings. Each non-dashed horizontal line is one
      # message, including an unlabelled one; its preceding arrowhead and all
      # immediately following text pieces form the same producer element.
      def legacy_reference_messages(extractor, doc)
        root = legacy_root(doc)
        return [] unless root

        children = root.element_children
        labelled = labelled_messages(extractor, children)
        return labelled unless labelled.empty?

        unlabelled_messages(extractor, children)
      end

      def labelled_messages(extractor, children)
        children.each_with_index.filter_map do |node, index|
          labelled_message(extractor, children, node, index)
        end
      end

      def labelled_message(extractor, children, node, index)
        return unless node.name == "text"

        prefix = preceding_run(children, index)
        return unless legacy_message_run?(prefix, node)

        texts = joined_label(children, node, index)
        labelled_message_element(extractor, prefix, texts, index)
      end

      def labelled_message_element(extractor, prefix, texts, index)
        geometry = texts.one? ? [*prefix, *texts] : prefix
        boxes = geometry.filter_map { |item| extractor.bbox(item) }
        box = Bbox.union(boxes)
        return unless box

        label = normalize(texts.map(&:text))
        Element.new(kind: :message, key: index, bbox: box,
                    label: label, identity: :label)
      end

      def joined_label(children, node, index)
        return [node] unless autonumber_piece?(node)

        [node, *children.drop(index + 1).take_while do |sibling|
          sibling.name == "text"
        end]
      end

      def autonumber_piece?(node)
        node["font-weight"] == "700" && node.text.match?(/\A\d+\z/)
      end

      def unlabelled_messages(extractor, children)
        message_lines(children).each_with_index.filter_map do |line, index|
          unlabelled_message(extractor, children, line, index)
        end
      end

      def unlabelled_message(extractor, children, line, index)
        run = unlabelled_message_run(children, line)
        boxes = run.filter_map { |item| extractor.bbox(item) }
        box = Bbox.union(boxes)
        return unless box

        Element.new(kind: :message, key: index + 1, bbox: box, label: "")
      end

      def message_lines(children)
        children.select do |node|
          horizontal_line?(node) && !dashed?(node)
        end
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
          normalize([text.text]) == normalize([label])
        end
      end

      def horizontal_line?(node)
        node.name == "line" && node["y1"] == node["y2"]
      end

      def preceding_run(children, index)
        children[0...index].reverse_each.take_while do |node|
          node.name != "text"
        end.reverse
      end

      def legacy_message_run?(run, node)
        run.any? { |item| horizontal_line?(item) } &&
          !fragment_header?(run, node)
      end

      def fragment_header?(run, node)
        fragment_separator?(run, node) ||
          (node["font-weight"] == "700" && run.last&.name == "rect")
      end

      def fragment_separator?(run, node)
        return false unless run.one?

        separator = run.first
        horizontal_line?(separator) && dashed?(separator) &&
          fragment_label?(node)
      end

      def fragment_label?(node)
        node["font-size"] == "11" && node["font-weight"] == "700" &&
          node.text.start_with?("[") && node.text.end_with?("]")
      end

      def unlabelled_message_run(children, line)
        index = children.index(line)
        arrowhead = children[index - 1]
        [arrowhead, line].compact
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

      def embedded_picture_element?(group)
        group.ancestors("g").any? do |ancestor|
          ancestor["id"].to_s.start_with?("note-")
        end
      end

      def normalize(texts)
        texts.join(" ").gsub(/\s+/, " ").strip
      end
    end
  end
end
