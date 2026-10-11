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
      RIGHT = "RIGHT"

      # @param graph [Hash] the graph to position in place
      # @return [Hash] the same graph
      # @raise [LayoutError] if elkrb cannot lay the graph out
      def self.apply(graph)
        new.apply(graph)
      end

      def apply(graph)
        options = graph[:layoutOptions] || {}
        place(graph, options)
        graph
      rescue Elkrb::Error => e
        raise LayoutError, "elkrb layout failed: #{e.message}"
      end

      private

      def place(graph, options)
        direction = options[Base::ElkOptions::DIRECTION] || DOWN
        return place_down(graph, options) if direction == DOWN
        return place_right(graph, options) if direction == RIGHT

        raise LayoutError,
              "elkrb layered cannot lay out direction #{direction}"
      end

      def place_down(graph, options)
        placed = Elkrb.layout(layout_input(graph), spacing(options))
        copy_layout(graph, placed)
      end

      def place_right(graph, options)
        placed = Elkrb.layout(layout_input(graph, transpose: true),
                              spacing(options))
        copy_right_layout(graph, placed)
      end

      def spacing(options)
        {
          spacing_node_node: options[Base::ElkOptions::NODE_NODE_SPACING],
          layer_spacing: options[Base::ElkOptions::LAYER_SPACING],
        }.compact
      end

      def layout_input(graph, transpose: false)
        input = graph.dup
        transpose_dimensions(input, graph) if transpose
        if graph[:children]
          input[:children] = graph[:children].map do |child|
            layout_input(child, transpose: transpose)
          end
        end
        if graph[:edges]
          input[:edges] = graph[:edges].reject { |edge| self_loop?(edge) }
        end
        input
      end

      def transpose_dimensions(input, graph)
        return unless graph.key?(:width) && graph.key?(:height)

        input[:width] = graph[:height]
        input[:height] = graph[:width]
      end

      def self_loop?(edge)
        source = edge[:sources]&.first
        source && source == edge[:targets]&.first
      end

      def copy_layout(graph, placed)
        copy_positions(graph[:children] || [], placed.children || [])
        copy_sections(graph[:edges] || [], placed.edges || [])
      end

      def copy_right_layout(graph, placed)
        copy_right_positions(graph[:children] || [], placed.children || [])
        copy_sections(graph[:edges] || [], placed.edges || [], transpose: true)
      end

      # elkrb keeps child order, so the two trees are walked in step.
      def copy_positions(children, placed)
        children.zip(placed).each do |child, result|
          child.merge!(x: result.x, y: result.y,
                       width: result.width, height: result.height)
          copy_layout(child, result)
        end
      end

      def copy_right_positions(children, placed)
        children.zip(placed).each do |child, result|
          child.merge!(x: result.y, y: result.x,
                       width: result.height, height: result.width)
          copy_right_layout(child, result)
        end
      end

      def copy_sections(edges, placed, transpose: false)
        placed_by_id = placed.group_by(&:id)
        edges.each do |edge|
          copy_edge_sections(edge, placed_by_id[edge[:id]]&.shift,
                             transpose: transpose)
        end
      end

      def copy_edge_sections(edge, result, transpose: false)
        return unless result

        sections = result.sections
        return if sections.nil? || sections.empty?

        edge[:sections] = sections.map do |section|
          section_hash(section, transpose: transpose)
        end
      end

      def section_hash(section, transpose: false)
        {
          startPoint: point_hash(section.start_point, transpose: transpose),
          endPoint: point_hash(section.end_point, transpose: transpose),
          bendPoints: (section.bend_points || []).map do |point|
            point_hash(point, transpose: transpose)
          end,
        }
      end

      def point_hash(point, transpose: false)
        return { x: point.y, y: point.x } if transpose

        { x: point.x, y: point.y }
      end
    end
  end
end
