# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Radar axes and curves keyed by their semantic labels on both producers.
    class RadarRecognizer
      def container_kinds
        []
      end

      def elements(extractor, doc)
        axes = nodes_with_class(doc, "radarAxisLabel", tag: "text")
        return reference_elements(extractor, doc, axes) if axes.any?

        candidate_elements(extractor, doc)
      end

      private

      def reference_elements(extractor, doc, axes)
        axis_elements = axes.filter_map do |text|
          labeled_element(extractor, text, text.text, :radar_axis)
        end
        curves = nodes_with_class(doc, "radarLegendText", tag: "text")
        curve_nodes = doc.xpath("//path[starts-with(@class, 'radarCurve-')]")
        titles = nodes_with_class(doc, "radarTitle", tag: "text")
        axis_elements + curve_elements(extractor, curve_nodes, curves) +
          title_elements(extractor, titles)
      end

      def candidate_elements(extractor, doc)
        axes = doc.xpath("//text[@font-size='14.0' and @font-weight]")
        axis_elements = axes.filter_map do |text|
          labeled_element(extractor, text, text.text, :radar_axis)
        end
        curve_nodes = doc.xpath("//polygon")
        legends = doc.xpath("//text[@font-size='12.0' and not(@font-weight)]")
        titles = doc.xpath("//text[@font-size='16.0' and @font-weight]")
        axis_elements + curve_elements(extractor, curve_nodes, legends) +
          title_elements(extractor, titles)
      end

      def curve_elements(extractor, curves, labels)
        curves.zip(labels).filter_map do |curve, label|
          labeled_element(extractor, curve, label&.text, :radar_curve)
        end
      end

      def title_elements(extractor, titles)
        titles.filter_map do |title|
          labeled_element(extractor, title, title.text, :radar_title)
        end
      end

      def labeled_element(extractor, node, raw_label, kind)
        label = raw_label.to_s.gsub(/\s+/, " ").strip
        box = extractor.bbox(node)
        return unless box && !label.empty?

        Element.new(kind: kind, key: label, bbox: box,
                    label: label, identity: :label)
      end

      def nodes_with_class(node, class_name, tag: "*")
        matcher = "contains(concat(' ', @class, ' '), ' #{class_name} ')"
        node.xpath("//#{tag}[#{matcher}]")
      end
    end
  end
end
