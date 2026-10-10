# frozen_string_literal: true

module Sirena
  module Layout
    class Sequence < Base
      # Reads frames and boxes back out of the sequence IR graph as plain
      # hashes, in the order the diagram declared them.
      module FrameReader
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
          nodes.group_by { |n| fields.dig(n.id, "owner_frame") }
            .transform_values do |group|
              group.map do |node|
                { label: node.label.to_s,
                  start: fields.dig(node.id, "start_index").to_i,
                  order: fields.dig(node.id, "order").to_i }
              end
            end
        end

        def frames(graph, fields, sections)
          graph.nodes.select { |n| n.role == "frame" }.map do |node|
            data = fields.fetch(node.id, {})
            { kind: data["frame_kind"], label: node.label.to_s,
              start: data["start_index"].to_i, stop: data["end_index"].to_i,
              depth: data["depth"].to_i,
              open_order: data["open_order"].to_i,
              close_order: data["close_order"].to_i,
              sections: sections.fetch(node.id, []) }
          end
        end

        def boxes(graph, fields)
          graph.nodes.select { |n| n.role == "box" }.map do |node|
            members = graph.edges.select do |edge|
              edge.role == "box_member" && edge.source_id == node.id
            end
            { title: node.label.to_s,
              color: fields.dig(node.id, "box_color"),
              members: members.map(&:target_id) }
          end
        end
      end
    end
  end
end
