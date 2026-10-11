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
      LEFT = "LEFT"
      RIGHT = "RIGHT"
      UP = "UP"

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
        return place_up(graph, options) if direction == UP
        return place_left(graph, options) if direction == LEFT

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

      def place_up(graph, options)
        placed = Elkrb.layout(layout_input(graph), spacing(options))
        copy_up_layout(graph, placed)
      end

      def place_left(graph, options)
        placed = Elkrb.layout(layout_input(graph, transpose: true),
                              spacing(options))
        copy_left_layout(graph, placed)
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
        copy_input_children(input, graph, transpose)
        copy_input_edges(input, graph)
        input
      end

      def copy_input_children(input, graph, transpose)
        return unless graph[:children]

        input[:children] = graph[:children].map do |child|
          layout_input(child, transpose: transpose)
        end
      end

      def copy_input_edges(input, graph)
        return unless graph[:edges]

        input[:edges] = graph[:edges].reject { |edge| self_loop?(edge) }
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

      def copy_up_layout(graph, placed)
        extent = reverse_extent(placed)
        copy_up_positions(graph[:children] || [], placed.children || [],
                          extent)
        copy_sections(graph[:edges] || [], placed.edges || [],
                      reverse_extent: extent)
      end

      def copy_left_layout(graph, placed)
        extent = reverse_extent(placed)
        copy_left_positions(graph[:children] || [], placed.children || [],
                            extent)
        options = { transpose: true, reverse_extent: extent }
        copy_sections(graph[:edges] || [], placed.edges || [], **options)
      end

      def reverse_extent(placed)
        children = placed.children || []
        return placed.height if children.empty?

        bottom = children.map { |child| child.y + child.height }.max
        return placed.height if extent_covers?(placed.height, bottom)

        reverse_origin(children, bottom)
      end

      def extent_covers?(extent, bottom)
        extent && extent >= bottom
      end

      def reverse_origin(children, bottom)
        children.map(&:y).min + bottom
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

      def copy_up_positions(children, placed, extent)
        children.zip(placed).each do |child, result|
          child.merge!(x: result.x, y: extent - result.y - result.height,
                       width: result.width, height: result.height)
          copy_up_layout(child, result)
        end
      end

      def copy_left_positions(children, placed, extent)
        children.zip(placed).each do |child, result|
          child.merge!(x: extent - result.y - result.height, y: result.x,
                       width: result.height, height: result.width)
          copy_left_layout(child, result)
        end
      end

      def copy_sections(edges, placed, transpose: false, reverse_extent: nil)
        placed_by_id = placed.group_by(&:id)
        edges.each do |edge|
          copy_edge_sections(edge, placed_by_id[edge[:id]]&.shift,
                             transpose: transpose,
                             reverse_extent: reverse_extent)
        end
      end

      def copy_edge_sections(edge, result, transpose: false,
                             reverse_extent: nil)
        return unless result

        sections = result.sections
        return if sections.nil? || sections.empty?

        options = { transpose: transpose, reverse_extent: reverse_extent }
        edge[:sections] = sections.map do |section|
          section_hash(section, **options)
        end
      end

      def section_hash(section, transpose: false, reverse_extent: nil)
        options = { transpose: transpose, reverse_extent: reverse_extent }
        {
          startPoint: point_hash(section.start_point, **options),
          endPoint: point_hash(section.end_point, **options),
          bendPoints: (section.bend_points || []).map do |point|
            point_hash(point, **options)
          end,
        }
      end

      def point_hash(point, transpose: false, reverse_extent: nil)
        result = if transpose
                   { x: point.y, y: point.x }
                 else
                   { x: point.x, y: point.y }
                 end
        reverse_point(result, transpose, reverse_extent)
      end

      def reverse_point(point, transpose, extent)
        return point unless extent

        axis = transpose ? :x : :y
        point.merge(axis => extent - point[axis])
      end
    end
  end
end
