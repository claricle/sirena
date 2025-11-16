# frozen_string_literal: true

require_relative '../diagram/treemap'

module Sirena
  module Transform
    # Layout calculator for treemap diagrams
    class Treemap
      PADDING = 10
      MIN_CELL_SIZE = 40
      LABEL_HEIGHT = 20
      HEADER_HEIGHT = 40

      # Transforms the diagram into a layout structure.
      #
      # @param diagram [Diagram::TreemapDiagram] the treemap diagram
      # @return [Hash] layout data with positioned cells and dimensions
      def to_graph(diagram)
        total_value = diagram.total_value
        return default_layout(diagram) if total_value <= 0

        # Calculate dimensions
        width = calculate_width(diagram)
        height = calculate_height(diagram)
        y_offset = diagram.title ? HEADER_HEIGHT + PADDING : PADDING

        # Layout root nodes
        cells = []
        x = PADDING
        y = y_offset

        diagram.root_nodes.each do |node|
          cell = layout_node(node, x, y, width - 2 * PADDING,
                            height - y_offset - PADDING, total_value)
          cells << cell if cell
          y += cell[:height] + PADDING if cell
        end

        {
          width: width,
          height: height,
          title: diagram.title,
          cells: cells,
          class_defs: diagram.class_defs
        }
      end

      private

      def layout_node(node, x, y, available_width, available_height, total_value)
        node_value = node.total_value
        return nil if node_value <= 0

        # Calculate proportional height
        ratio = node_value / total_value
        height = [available_height * ratio, MIN_CELL_SIZE].max

        cell = {
          label: node.label,
          value: node_value,
          x: x,
          y: y,
          width: available_width,
          height: height,
          css_class: node.css_class,
          depth: node.depth,
          children: []
        }

        # If this node has children, layout them recursively
        if node.branch? && node.children.any?
          child_y = y + LABEL_HEIGHT
          child_height = height - LABEL_HEIGHT - PADDING

          node.children.each do |child|
            child_cell = layout_node(child, x + PADDING, child_y,
                                     available_width - 2 * PADDING,
                                     child_height, node_value)
            if child_cell
              cell[:children] << child_cell
              child_y += child_cell[:height] + PADDING
            end
          end
        end

        cell
      end

      def calculate_width(diagram)
        # Base width calculation
        800
      end

      def calculate_height(diagram)
        # Calculate based on number of nodes
        node_count = count_nodes(diagram.root_nodes)
        base_height = 400
        additional_height = [node_count * 30, 200].min

        base_height + additional_height
      end

      def count_nodes(nodes)
        nodes.sum do |node|
          1 + (node.children ? count_nodes(node.children) : 0)
        end
      end

      def default_layout(diagram)
        {
          width: 800,
          height: 400,
          title: diagram.title,
          cells: [],
          class_defs: diagram.class_defs
        }
      end
    end
  end
end