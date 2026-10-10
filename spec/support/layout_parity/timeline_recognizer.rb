# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Timeline periods and events keyed by their visible labels.
    class TimelineRecognizer
      NODE = "contains(concat(' ', @class, ' '), ' timeline-node ')"
      SECTION_NODES = "//g[#{NODE}]" \
                      "[not(ancestor::g[contains(@class, 'Wrapper')])]".freeze
      AXIS_LINE = "(//g[@class='lineWrapper'])[last()]" \
                  "/*[self::line or self::path][1]"

      def container_kinds
        []
      end

      def elements(extractor, doc)
        tasks = nodes_with_class(doc, "taskWrapper")
        items = if tasks.any?
                  reference_elements(extractor, doc, tasks)
                else
                  candidate_elements(extractor, doc)
                end
        items + section_elements(extractor, doc) +
          axis_elements(extractor, doc)
      end

      private

      def reference_elements(extractor, doc, tasks)
        periods = tasks.filter_map do |node|
          element(extractor, node, extractor.label(node), :timeline_period)
        end
        events = nodes_with_class(doc, "eventWrapper").filter_map do |node|
          element(extractor, node, extractor.label(node), :timeline_event)
        end
        periods + events
      end

      def section_elements(extractor, doc)
        doc.xpath(SECTION_NODES).filter_map do |node|
          element(extractor, node, normalized(node), :timeline_section)
        end
      end

      def axis_elements(extractor, doc)
        doc.xpath(AXIS_LINE).filter_map do |node|
          element(extractor, node, "axis", :timeline_axis)
        end
      end

      def candidate_elements(extractor, doc)
        doc.xpath("//circle").flat_map do |marker|
          marker_elements(extractor, marker)
        end
      end

      def marker_elements(extractor, marker)
        texts = texts_through_period(marker)
        period = texts.pop
        events = texts.filter_map do |text|
          element(extractor, text, normalized(text), :timeline_event)
        end
        period_element = element(
          extractor, marker, normalized(period), :timeline_period
        )
        [period_element, *events].compact
      end

      def texts_through_period(marker)
        texts = []
        node = marker.next_element
        while node && node.name != "circle"
          texts << node if node.name == "text"
          break if period?(node)

          node = node.next_element
        end
        texts
      end

      def period?(node)
        node.name == "text" && !node["font-weight"].to_s.empty?
      end

      def element(extractor, node, label, kind)
        box = extractor.bbox(node)
        return unless box && !label.empty?

        Element.new(kind: kind, key: label, bbox: box,
                    label: label, identity: :label)
      end

      def nodes_with_class(doc, class_name)
        matcher = "contains(concat(' ', @class, ' '), ' #{class_name} ')"
        doc.xpath("//g[#{matcher}]")
      end

      def normalized(text)
        return "" unless text

        text.text.gsub(/\s+/, " ").strip
      end
    end
  end
end
