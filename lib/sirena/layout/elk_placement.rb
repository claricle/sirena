# frozen_string_literal: true

require "elkrb"
require_relative "base"

module Sirena
  module Layout
    # Positions an ELK-shaped graph Hash with elkrb's layered algorithm.
    #
    # Same contract as Grid.apply: x/y/width/height are written into the
    # Hash in place, a child positioned inside its parent. An elkrb
    # failure raises LayoutError; nothing falls back to Grid.
    #
    # elkrb 1.0.2's layered algorithm reads no `elk.direction` and takes
    # its spacing from the options argument, not the graph's
    # layoutOptions, so both are handled here.
    class ElkPlacement
      DOWN = "DOWN"

      # @param graph [Hash] the graph to position in place
      # @return [Hash] the same graph
      # @raise [LayoutError] if elkrb cannot lay the graph out
      def self.apply(graph)
        new.apply(graph)
      end

      def apply(graph)
        options = graph[:layoutOptions] || {}
        require_downward(options)
        placed = Elkrb.layout(layout_input(graph), spacing(options))
        copy_layout(graph, placed)
        graph
      rescue Elkrb::Error => e
        raise LayoutError, "elkrb layout failed: #{e.message}"
      end

      private

      def require_downward(options)
        direction = options[Base::ElkOptions::DIRECTION] || DOWN
        return if direction == DOWN

        raise LayoutError,
              "elkrb layered cannot lay out direction #{direction}"
      end

      def spacing(options)
        {
          spacing_node_node: options[Base::ElkOptions::NODE_NODE_SPACING],
          layer_spacing: options[Base::ElkOptions::LAYER_SPACING],
        }.compact
      end

      def layout_input(graph)
        input = graph.dup
        if graph[:children]
          input[:children] = graph[:children].map do |child|
            layout_input(child)
          end
        end
        if graph[:edges]
          input[:edges] = graph[:edges].reject { |edge| self_loop?(edge) }
        end
        input
      end

      def self_loop?(edge)
        source = edge[:sources]&.first
        source && source == edge[:targets]&.first
      end

      def copy_layout(graph, placed)
        copy_positions(graph[:children] || [], placed.children || [])
        copy_sections(graph[:edges] || [], placed.edges || [])
      end

      # elkrb keeps child order, so the two trees are walked in step.
      def copy_positions(children, placed)
        children.zip(placed).each do |child, result|
          child.merge!(x: result.x, y: result.y,
                       width: result.width, height: result.height)
          copy_layout(child, result)
        end
      end

      def copy_sections(edges, placed)
        placed_by_id = placed.group_by(&:id)
        edges.each do |edge|
          copy_edge_sections(edge, placed_by_id[edge[:id]]&.shift)
        end
      end

      def copy_edge_sections(edge, result)
        return unless result

        sections = result.sections
        return if sections.nil? || sections.empty?

        edge[:sections] = sections.map { |section| section_hash(section) }
      end

      def section_hash(section)
        {
          startPoint: point_hash(section.start_point),
          endPoint: point_hash(section.end_point),
          bendPoints: (section.bend_points || []).map do |point|
            point_hash(point)
          end,
        }
      end

      def point_hash(point)
        { x: point.x, y: point.y }
      end
    end
  end
end
