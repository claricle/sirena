# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Gantt task shapes and date ticks shared by mmdc and Sirena SVGs.
    class GanttRecognizer
      TASK_LABEL = /(?:taskText|milestoneText|activeText|doneText|critText)/

      def container_kinds
        []
      end

      def elements(extractor, doc)
        if reference?(doc)
          reference_tasks(extractor, doc) + reference_ticks(extractor, doc)
        else
          sirena_tasks(extractor, doc) + sirena_ticks(extractor, doc)
        end
      end

      private

      def reference?(doc)
        doc.xpath("//*[contains(concat(' ', @class, ' '), ' grid ')]").any?
      end

      def reference_tasks(extractor, doc)
        labels = reference_task_labels(extractor, doc)
        task_shapes(doc).filter_map do |shape|
          label = closest_label(extractor, shape, labels)
          task_element(extractor, shape, label)
        end
      end

      def reference_task_labels(extractor, doc)
        text_entries(extractor, doc).select do |entry|
          entry[:node]["class"].to_s.split.any? do |name|
            TASK_LABEL.match?(name)
          end
        end
      end

      def task_shapes(doc)
        doc.xpath("//rect | //polygon | //path").select do |shape|
          shape["class"].to_s.split.intersect?(%w[task milestone])
        end
      end

      def closest_label(extractor, shape, labels)
        box = extractor.bbox(shape)
        labels.min_by { |entry| distance(box.center, entry[:box].center) }
      end

      def reference_ticks(extractor, doc)
        xpath = "//*[contains(concat(' ', @class, ' '), ' tick ')]//text"
        nodes = doc.xpath(xpath)
        tick_elements(extractor, nodes)
      end

      def sirena_tasks(extractor, doc)
        texts = text_entries(extractor, doc)
        sirena_shapes(doc).filter_map do |shape|
          label = outside_row_label(extractor, shape, texts)
          task_element(extractor, shape, label)
        end
      end

      def sirena_shapes(doc)
        doc.xpath("//rect | //polygon")
      end

      def outside_row_label(extractor, shape, texts)
        box = extractor.bbox(shape)
        candidates = texts.select { |entry| outside_row?(entry[:box], box) }
        candidates.min_by { |entry| distance(box.center, entry[:box].center) }
      end

      def outside_row?(label, shape)
        tolerance = [shape.height / 2, 8].max
        label.max_x < shape.min_x &&
          (label.center.last - shape.center.last).abs <= tolerance
      end

      def sirena_ticks(extractor, doc)
        timeline = sirena_timeline(extractor, doc)
        return [] unless timeline

        nodes = doc.xpath("//text").select do |text|
          timeline.contain?(extractor.bbox(text))
        end
        tick_elements(extractor, nodes)
      end

      def sirena_timeline(extractor, doc)
        lines = doc.xpath("//line").filter_map { |line| extractor.bbox(line) }
        doc.xpath("//rect").filter_map do |rect|
          box = extractor.bbox(rect)
          box if lines.any? { |line| starts_below?(line, box) }
        end.first
      end

      def starts_below?(line, box)
        aligned = (line.min_y - box.max_y).abs <= 0.01
        inside = line.min_x.between?(box.min_x, box.max_x)
        line.width.zero? && aligned && inside
      end

      def tick_elements(extractor, nodes)
        nodes.filter_map do |node|
          entry = text_entry(extractor, node)
          logical_element(:tick, entry[:label], entry[:box]) if entry
        end
      end

      def task_element(extractor, shape, label)
        box = extractor.bbox(shape)
        logical_element(:task, label[:label], box) if box && label
      end

      def logical_element(kind, label, box)
        Element.new(kind: kind, key: label, bbox: box, label: label,
                    identity: :label)
      end

      def text_entries(extractor, doc)
        doc.xpath("//text").filter_map { |text| text_entry(extractor, text) }
      end

      def text_entry(extractor, node)
        box = extractor.bbox(node)
        label = node.text.gsub(/\s+/, " ").strip
        { node: node, box: box, label: label } if box && !label.empty?
      end

      def distance(left, right)
        Math.hypot(left[0] - right[0], left[1] - right[1])
      end
    end
  end
end
