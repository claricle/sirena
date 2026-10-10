# frozen_string_literal: true

module Sirena
  module Layout
    class Sequence < Base
      # Reads frames and boxes back out of the sequence IR graph as plain
      # hashes, in the order the diagram declared them.
      module FrameReader
        INTEGER_FIELDS = {
          start: "start_index", stop: "end_index", depth: "depth",
          open_order: "open_order", close_order: "close_order"
        }.freeze

        module_function

        # @param graph [IR::Graph] the sequence graph
        # @return [Hash] `frames:` and `boxes:` hash lists
        def call(graph)
          fields = fields_by_parent(graph)
          sections = sections_by_frame(graph, fields)
          { frames: frames(graph, fields, sections),
            boxes: boxes(graph, fields) }
        end

        def fields_by_parent(graph)
          graph.nodes.each_with_object({}) do |node, index|
            next unless node.parent_id

            (index[node.parent_id] ||= {})[node.role] = node.label
          end
        end

        def sections_by_frame(graph, fields)
          nodes = graph.nodes.select { |n| n.role == "frame_section" }
          grouped = nodes.group_by { |n| fields.dig(n.id, "owner_frame") }
          grouped.transform_values do |group|
            group.map { |node| section(node, fields.fetch(node.id, {})) }
          end
        end

        def section(node, data)
          { label: node.label.to_s, start: data["start_index"].to_i,
            order: data["order"].to_i }
        end

        def frames(graph, fields, sections)
          graph.nodes.select { |n| n.role == "frame" }.map do |node|
            frame(node, fields.fetch(node.id, {}), sections.fetch(node.id, []))
          end
        end

        def frame(node, data, sections)
          record = { kind: data["frame_kind"], label: node.label.to_s,
                     sections: sections }
          record.merge(INTEGER_FIELDS.transform_values { |k| data[k].to_i })
        end

        def boxes(graph, fields)
          graph.nodes.select { |n| n.role == "box" }.map do |node|
            { title: node.label.to_s,
              color: fields.dig(node.id, "box_color"),
              members: box_members(graph, node) }
          end
        end

        def box_members(graph, box)
          members = graph.edges.select do |edge|
            edge.role == "box_member" && edge.source_id == box.id
          end
          members.map(&:target_id)
        end
      end
    end
  end
end
