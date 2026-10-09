# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Journey sections and tasks keyed by their visible semantic labels.
    class UserJourneyRecognizer
      def container_kinds
        []
      end

      def elements(extractor, doc)
        return reference_elements(extractor, doc) if reference?(doc)

        candidate_elements(extractor, doc)
      end

      private

      def reference?(doc)
        nodes_with_class(doc, "journey-section", tag: "rect").any?
      end

      def reference_elements(extractor, doc)
        sections = wrapper_elements(
          extractor, doc, "journey-section", :journey_section
        )
        tasks = wrapper_elements(extractor, doc, "task", :journey_task)
        sections + tasks
      end

      def wrapper_elements(extractor, doc, class_name, kind)
        labels = nodes_with_class(doc, class_name, tag: "text")
        labels.filter_map do |label_node|
          wrapper = label_node.ancestors("g").first
          element(extractor, wrapper, label_node, kind)
        end
      end

      def candidate_elements(extractor, doc)
        sections = candidate_sections(doc).filter_map do |text|
          element(extractor, text, text, :journey_section)
        end
        task_groups = doc.xpath("//g[starts-with(@id, 'task-')]")
        tasks = task_groups.filter_map do |group|
          element(extractor, group, group.xpath("./text").first, :journey_task)
        end
        sections + tasks
      end

      def candidate_sections(doc)
        doc.xpath("//text").select do |text|
          sibling = text.next_element
          sibling&.name == "g" && sibling["id"].to_s.start_with?("task-")
        end
      end

      def element(extractor, node, label_node, kind)
        return unless node && label_node

        label = normalized(label_node)
        box = extractor.bbox(node)
        return unless box && !label.empty?

        Element.new(kind: kind, key: label, bbox: box,
                    label: label, identity: :label)
      end

      def nodes_with_class(node, class_name, tag: "*")
        matcher = "contains(concat(' ', @class, ' '), ' #{class_name} ')"
        node.xpath("//#{tag}[#{matcher}]")
      end

      def normalized(text)
        text.text.gsub(/\s+/, " ").strip
      end
    end
  end
end
