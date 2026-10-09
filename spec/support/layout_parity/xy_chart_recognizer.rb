# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # XY bar marks and line series, keyed by stable producer-neutral ordinals.
    class XyChartRecognizer
      def container_kinds
        []
      end

      def elements(extractor, doc)
        bars = reference_bars(doc)
        return reference_elements(extractor, doc, bars) if bars.any?

        candidate_elements(extractor, doc)
      end

      private

      def reference_elements(extractor, doc, bars)
        bar_elements(extractor, bars) +
          line_elements(extractor, reference_lines(doc))
      end

      def candidate_elements(extractor, doc)
        bars = doc.xpath("//rect[following::circle]")
        bar_elements(extractor, bars) +
          line_elements(extractor, doc.xpath("//polyline"))
      end

      def reference_bars(doc)
        matcher = "contains(concat(' ', @class, ' '), ' bar-plot-0 ')"
        doc.xpath("//g[#{matcher}]/rect")
      end

      def reference_lines(doc)
        matcher = "contains(concat(' ', @class, ' '), ' line-plot-1 ')"
        doc.xpath("//g[#{matcher}]/path")
      end

      def bar_elements(extractor, bars)
        ordinal_elements(extractor, bars, :xy_bar, "bar")
      end

      def line_elements(extractor, lines)
        ordinal_elements(extractor, lines, :xy_line, "line")
      end

      def ordinal_elements(extractor, nodes, kind, prefix)
        nodes.each_with_index.filter_map do |node, index|
          box = extractor.bbox(node)
          next unless box

          key = "#{prefix}-#{index + 1}"
          Element.new(kind: kind, key: key, bbox: box)
        end
      end
    end
  end
end
