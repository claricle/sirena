# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # C4 boundaries and elements keyed by their visible semantic labels.
    class C4Recognizer
      def container_kinds
        [:c4_boundary]
      end

      def elements(extractor, doc)
        boundaries(extractor, doc) + logical_elements(extractor, doc)
      end

      private

      def boundaries(extractor, doc)
        boundary_rects(doc).filter_map do |rect|
          group = rect.ancestors("g").first
          next unless group

          label = group.xpath(".//text").first&.text
          labeled_element(extractor, rect, label, :c4_boundary)
        end
      end

      def boundary_rects(doc)
        doc.xpath("//rect[@stroke-dasharray]")
      end

      def logical_elements(extractor, doc)
        reference = nodes_with_class(doc, "person-man")
        if reference.any?
          return reference.filter_map do |node|
            reference_element(extractor, node)
          end
        end

        candidate_elements(extractor, doc)
      end

      def reference_element(extractor, node)
        labeled_element(extractor, node, name_text(node), :c4_element)
      end

      def candidate_elements(extractor, doc)
        doc.xpath("//g[starts-with(@id, 'element-')]").filter_map do |node|
          labeled_element(extractor, node, name_text(node), :c4_element)
        end
      end

      # The first text of an element is its "<<stereotype>>"; the name is next.
      # An element declared with an empty name keeps an empty name text on both
      # producers, so its description is the first visible label to key on.
      def name_text(node)
        node.xpath(".//text")[1..].to_a.map(&:text)
          .find { |text| !text.strip.empty? }
      end

      def labeled_element(extractor, node, raw_label, kind)
        label = raw_label.to_s.gsub(/\s+/, " ").strip
        box = extractor.bbox(node)
        return unless box && !label.empty?

        Element.new(kind: kind, key: label, bbox: box,
                    label: label, identity: :label)
      end

      def nodes_with_class(node, class_name)
        matcher = "contains(concat(' ', @class, ' '), ' #{class_name} ')"
        node.xpath("//g[#{matcher}]")
      end
    end
  end
end
