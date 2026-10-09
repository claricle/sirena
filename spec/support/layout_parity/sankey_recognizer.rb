# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Sankey nodes keyed by labels and flows keyed by endpoint labels.
    class SankeyRecognizer
      def container_kinds
        []
      end

      def elements(extractor, doc)
        nodes = node_entries(extractor, doc)
        node_elements(nodes) + flow_elements(extractor, doc, nodes)
      end

      private

      def node_entries(extractor, doc)
        groups = doc.xpath("//g[contains(concat(' ', @class, ' '), " \
                           "' nodes ')]/g[contains(concat(' ', @class, ' '), " \
                           "' node ')]")
        return reference_nodes(extractor, doc, groups) if groups.any?

        candidate_nodes(extractor, doc)
      end

      def reference_nodes(extractor, doc, groups)
        labels = doc.xpath("//g[contains(concat(' ', @class, ' '), " \
                           "' node-labels ')]/text")
        groups.zip(labels).filter_map do |group, text|
          node_entry(extractor, group, first_line(text))
        end
      end

      def candidate_nodes(extractor, doc)
        texts = doc.xpath("//text[@font-weight]")
        doc.xpath("//rect").filter_map do |rect|
          box = extractor.bbox(rect)
          text = texts.find do |candidate|
            contained?(extractor, candidate, box)
          end
          node_entry(extractor, rect, normalized(text)) if text
        end
      end

      def contained?(extractor, text, box)
        anchor = extractor.bbox(text)
        box && anchor && box.contain?(anchor)
      end

      def node_entry(extractor, shape, label)
        box = extractor.bbox(shape)
        return unless box && !label.empty?

        { label: label, box: box }
      end

      def node_elements(nodes)
        nodes.map do |node|
          Element.new(kind: :sankey_node, key: node[:label],
                      bbox: node[:box], label: node[:label], identity: :label)
        end
      end

      def flow_elements(extractor, doc, nodes)
        ordinals = Hash.new(0)
        flow_paths(doc).filter_map do |path|
          endpoints = endpoint_labels(path, nodes)
          next unless endpoints

          ordinals[endpoints] += 1
          flow_element(extractor, path, endpoints, ordinals[endpoints])
        end
      end

      def flow_paths(doc)
        links = doc.xpath("//g[contains(concat(' ', @class, ' '), " \
                          "' links ')]/g[contains(concat(' ', @class, ' '), " \
                          "' link ')]/path")
        links.any? ? links : doc.xpath("//path")
      end

      def endpoint_labels(path, nodes)
        endpoints = path_endpoints(path)
        return unless endpoints && nodes.any?

        source_point, target_point = endpoints
        source_boundary, target_boundary =
          boundaries(source_point, target_point)
        source = closest_node(source_point, nodes, source_boundary)
        target = closest_node(target_point, nodes, target_boundary)
        [source[:label], target[:label]]
      end

      def path_endpoints(path)
        tokens = path["d"].to_s.scan(PathPoints::TOKEN)
        move = command_values(tokens, "m", 2)
        cubic = command_values(tokens, "c", 6)
        return unless move && cubic

        source = move.last
        target = cubic.last.last(2)
        target = relative_target(source, target) if cubic.first == "c"
        [source, target]
      end

      def command_values(tokens, command, count)
        index = tokens.index { |token| token.casecmp?(command) }
        return unless index

        values = tokens.slice(index + 1, count).map(&:to_f)
        [tokens[index], values]
      end

      def relative_target(source, target)
        source.zip(target).map { |origin, offset| origin + offset }
      end

      def boundaries(source, target)
        return %i[min_x max_x] if target.first < source.first

        %i[max_x min_x]
      end

      def closest_node(point, nodes, boundary)
        nodes.min_by do |node|
          box = node[:box]
          x_distance = (box.public_send(boundary) - point.first).abs
          Math.hypot(x_distance, vertical_distance(point.last, box))
        end
      end

      def vertical_distance(y_coordinate, box)
        return box.min_y - y_coordinate if y_coordinate < box.min_y
        return y_coordinate - box.max_y if y_coordinate > box.max_y

        0
      end

      def flow_element(extractor, path, endpoints, ordinal)
        box = extractor.bbox(path)
        return unless box

        Element.new(kind: :sankey_flow,
                    key: [*endpoints, ordinal], bbox: box,
                    identity: :label)
      end

      def first_line(text)
        text&.text.to_s.lines.first.to_s.strip
      end

      def normalized(text)
        text&.text.to_s.gsub(/\s+/, " ").strip
      end
    end
  end
end
