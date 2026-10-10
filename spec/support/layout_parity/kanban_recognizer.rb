# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Kanban sections and cards shared by mmdc references and Sirena renders.
    class KanbanRecognizer
      def container_kinds
        [:section]
      end

      def elements(extractor, doc)
        reference = reference_elements(extractor, doc)
        reference.empty? ? sirena_elements(extractor, doc) : reference
      end

      private

      def reference_elements(extractor, doc)
        doc.xpath("//g[@id]").filter_map do |group|
          kind = reference_kind(group)
          next unless kind

          label = reference_label(extractor, group, kind)
          box = extractor.bbox(group)
          logical_element(kind, label, box) if box && !label.empty?
        end
      end

      def reference_label(extractor, group, kind)
        return extractor.label(group) unless kind == :card

        primary = group.xpath("./g").find do |child|
          child["class"].to_s.split.include?("label")
        end
        extractor.label(primary || group)
      end

      def reference_kind(group)
        classes = group["class"].to_s.split
        return :section if classes.include?("cluster")

        :card if classes.include?("node")
      end

      def sirena_elements(extractor, doc)
        rects = rectangles(extractor, doc)
        maximal(rects).flat_map do |section|
          section_elements(extractor, doc, section, rects)
        end
      end

      def rectangles(extractor, doc)
        doc.xpath("//rect").filter_map do |node|
          box = extractor.bbox(node)
          { node: node, box: box } if box
        end
      end

      def maximal(rects)
        rects.reject do |rect|
          rects.any? do |other|
            other != rect && other[:box].enclose?(rect[:box])
          end
        end
      end

      def section_elements(extractor, doc, section, rects)
        children = direct_children(section, rects)
        header = children.find { |child| header?(section[:box], child[:box]) }
        return [] unless header

        title = nearest_label(extractor, doc, header[:box])
        cards = card_elements(extractor, doc, children, header)
        [logical_element(:section, title, section[:box]), *cards].compact
      end

      def card_elements(extractor, doc, children, header)
        children.reject { |child| child == header }.filter_map do |card|
          label = first_label(extractor, doc, card[:box])
          logical_element(:card, label, card[:box]) if label
        end
      end

      def direct_children(parent, rects)
        enclosed = rects.reject { |rect| rect == parent }
          .select { |rect| parent[:box].enclose?(rect[:box]) }
        enclosed.reject do |child|
          enclosed.any? do |middle|
            middle != child && middle[:box].enclose?(child[:box])
          end
        end
      end

      def header?(section, candidate)
        [section.min_x, section.min_y, section.max_x] ==
          [candidate.min_x, candidate.min_y, candidate.max_x]
      end

      def nearest_label(extractor, doc, box)
        labels_in(extractor, doc, box).min_by do |entry|
          distance(entry[:box].center, box.center)
        end&.fetch(:label)
      end

      def first_label(extractor, doc, box)
        labels_in(extractor, doc, box)
          .min_by { |entry| [entry[:box].min_y, entry[:box].min_x] }
          &.fetch(:label)
      end

      def labels_in(extractor, doc, box)
        doc.xpath("//text").filter_map do |text|
          label_entry(extractor, text, box)
        end
      end

      def label_entry(extractor, text, box)
        anchor = extractor.bbox(text)
        return unless anchor && box.contain?(anchor)

        label = normalized_text(text)
        { box: anchor, label: label } unless label.empty?
      end

      def normalized_text(text)
        lines = text.xpath("./tspan")
        content = lines.empty? ? text.text : lines.map(&:text).join(" ")
        content.gsub(/\s+/, " ").strip
      end

      def distance(left, right)
        Math.hypot(left[0] - right[0], left[1] - right[1])
      end

      def logical_element(kind, label, box)
        return unless label

        Element.new(kind: kind, key: label, bbox: box, label: label,
                    identity: :label)
      end
    end
  end
end
