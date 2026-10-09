# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Pie sectors associated with their semantic legend labels on both sides.
    class PieRecognizer
      FILL = /fill:\s*([^;]+)/
      NUMBER = /-?\d+(?:\.\d+)?/
      BRACKETED_VALUE = /\s*\[\s*#{NUMBER}\s*\]\z/o
      PERCENT_VALUE = /:\s*#{NUMBER}%\z/o

      def container_kinds
        []
      end

      def elements(extractor, doc)
        paths = pie_paths(doc)
        labels = legend_labels(doc, paths)

        paths.filter_map do |path|
          label = labels.fetch(path.pointer_id, nil)
          box = extractor.bbox(path)
          next unless box && label

          Element.new(kind: :pie_sector, key: label, bbox: box,
                      label: label, identity: :label)
        end
      end

      private

      def pie_paths(doc)
        reference = nodes_with_class(doc, "pieCircle", tag: "path")
        return reference if reference.any?

        doc.xpath("//path[starts-with(@id, 'slice-')]")
          .sort_by { |path| path["id"].delete_prefix("slice-").to_i }
      end

      def legend_labels(doc, paths)
        legends = nodes_with_class(doc, "legend", tag: "g")
        return reference_labels(legends, paths) if legends.any?

        candidate_labels(doc, paths)
      end

      def reference_labels(legends, paths)
        by_color = legends.to_h do |legend|
          rect = legend.at_xpath(".//rect")
          [color(rect&.[]("style").to_s[FILL, 1]), label_of(legend)]
        end
        paths.to_h { |path| [path.pointer_id, by_color[color(path["fill"])]] }
      end

      def candidate_labels(doc, paths)
        texts = doc.xpath("//text[not(@font-weight)]").to_a.last(paths.size)
        paths.zip(texts).to_h do |path, text|
          [path.pointer_id, section_label(text&.text)]
        end
      end

      def color(value)
        numbers = value.to_s.scan(NUMBER).map(&:to_f)
        return hex_rgb(value) if value.to_s.start_with?("#")
        return numbers.first(3).map(&:round) if value.to_s.start_with?("rgb")
        return hsl_rgb(*numbers.first(3)) if value.to_s.start_with?("hsl")

        value
      end

      def hex_rgb(value)
        hex = value.delete_prefix("#")
        hex = hex.chars.map { |digit| digit * 2 }.join if hex.length == 3
        hex.scan(/../).map { |pair| pair.to_i(16) }
      end

      def hsl_rgb(hue, saturation, lightness)
        saturation /= 100.0
        lightness /= 100.0
        chroma = (1 - ((2 * lightness) - 1).abs) * saturation
        scale_rgb(hsl_channels(hue, chroma), lightness, chroma)
      end

      def hsl_channels(hue, chroma)
        sector = (hue % 360) / 60.0
        secondary = chroma * (1 - ((sector % 2) - 1).abs)
        hsl_sector(sector, chroma, secondary)
      end

      def scale_rgb(rgb, lightness, chroma)
        offset = lightness - (chroma / 2)
        rgb.map { |channel| ((channel + offset) * 255).round }
      end

      def hsl_sector(sector, chroma, secondary)
        return [chroma, secondary, 0] if sector < 1
        return [secondary, chroma, 0] if sector < 2
        return [0, chroma, secondary] if sector < 3
        return [0, secondary, chroma] if sector < 4
        return [secondary, 0, chroma] if sector < 5

        [chroma, 0, secondary]
      end

      def label_of(node)
        section_label(node.at_xpath(".//text")&.text)
      end

      def section_label(text)
        text.to_s.gsub(BRACKETED_VALUE, "")
          .gsub(PERCENT_VALUE, "").gsub(/\s+/, " ").strip
      end

      def nodes_with_class(node, class_name, tag: "*")
        matcher = "contains(concat(' ', @class, ' '), ' #{class_name} ')"
        node.xpath("//#{tag}[#{matcher}]")
      end
    end
  end
end
