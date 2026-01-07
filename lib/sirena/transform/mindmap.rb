# frozen_string_literal: true

module Sirena
  module Transform
    # Transforms a Mindmap diagram into a positioned layout structure.
    #
    # The layout algorithm handles:
    # - Tree-based layout with root at center
    # - Radial positioning of branches
    # - Level-based spacing
    # - Connection path calculation
    #
    # @example Transform a mindmap
    #   transform = Transform::Mindmap.new
    #   layout = transform.to_graph(diagram)
    class Mindmap
      # Horizontal spacing between sibling nodes
      NODE_HORIZONTAL_SPACING = 120

      # Vertical spacing between levels
      LEVEL_VERTICAL_SPACING = 80

      # Default node dimensions
      DEFAULT_NODE_WIDTH = 100
      DEFAULT_NODE_HEIGHT = 40

      # Padding for root node
      ROOT_PADDING = 20

      # Transforms the diagram into a layout structure.
      #
      # @param diagram [Diagram::Mindmap] the mindmap diagram
      # @return [Hash] layout data with nodes and connections
      def to_graph(diagram)
        return empty_graph unless diagram.root

        # Position nodes using tree layout
        positioned_nodes = position_tree(diagram.root)

        # Build connections between nodes
        connections = build_connections(diagram.root)

        # Calculate bounds
        bounds = calculate_bounds(positioned_nodes)

        {
          nodes: positioned_nodes,
          connections: connections,
          width: bounds[:width],
          height: bounds[:height],
          root: positioned_nodes.first
        }
      end

      private

      def empty_graph
        {
          nodes: [],
          connections: [],
          width: 0,
          height: 0,
          root: nil
        }
      end

      # Positions nodes in a tree layout
      #
      # @param root [Diagram::Mindmap::MindmapNode] root node
      # @return [Array<Hash>] positioned nodes
      def position_tree(root)
        nodes = []

        # Start with root at center-top
        root_width = estimate_node_width(root)
        root_height = estimate_node_height(root)

        # Calculate tree width to center root
        tree_width = calculate_tree_width(root)
        root_x = tree_width / 2

        # Position root
        nodes << {
          id: root.id,
          content: root.content,
          x: root_x,
          y: ROOT_PADDING,
          width: root_width,
          height: root_height,
          level: root.level,
          shape: root.shape,
          icon: root.icon,
          classes: root.classes,
          original: root
        }

        # Position children recursively
        if root.children.any?
          position_children(
            root,
            root_x,
            ROOT_PADDING + root_height + LEVEL_VERTICAL_SPACING,
            nodes
          )
        end

        nodes
      end

      # Positions children of a node
      #
      # @param parent [Diagram::Mindmap::MindmapNode] parent node
      # @param parent_x [Numeric] parent X position
      # @param y [Numeric] Y position for this level
      # @param nodes [Array<Hash>] accumulator for positioned nodes
      def position_children(parent, parent_x, y, nodes)
        children = parent.children
        return if children.empty?

        # Calculate total width needed for all children
        total_width = children.sum { |c| estimate_subtree_width(c) }
        total_width += (children.size - 1) * NODE_HORIZONTAL_SPACING

        # Start x position (centered under parent)
        start_x = parent_x - (total_width / 2)
        current_x = start_x

        children.each do |child|
          child_width = estimate_node_width(child)
          child_height = estimate_node_height(child)
          subtree_width = estimate_subtree_width(child)

          # Center the node within its subtree space
          node_x = current_x + (subtree_width / 2)

          nodes << {
            id: child.id,
            content: child.content,
            x: node_x,
            y: y,
            width: child_width,
            height: child_height,
            level: child.level,
            shape: child.shape,
            icon: child.icon,
            classes: child.classes,
            parent_id: parent.id,
            original: child
          }

          # Recursively position grandchildren
          if child.children.any?
            position_children(
              child,
              node_x,
              y + child_height + LEVEL_VERTICAL_SPACING,
              nodes
            )
          end

          current_x += subtree_width + NODE_HORIZONTAL_SPACING
        end
      end

      # Estimates the width of a single node based on content and shape
      #
      # @param node [Diagram::Mindmap::MindmapNode] node
      # @return [Numeric] estimated width
      def estimate_node_width(node)
        # Base width on content length
        content_length = node.content.to_s.length
        base_width = [content_length * 8 + 20, DEFAULT_NODE_WIDTH].max

        # Adjust for shape
        case node.shape
        when "circle", "hexagon"
          base_width * 1.2
        else
          base_width
        end
      end

      # Estimates the height of a node
      #
      # @param node [Diagram::Mindmap::MindmapNode] node
      # @return [Numeric] estimated height
      def estimate_node_height(node)
        DEFAULT_NODE_HEIGHT
      end

      # Calculates the total width needed for a subtree
      #
      # @param node [Diagram::Mindmap::MindmapNode] root of subtree
      # @return [Numeric] total width
      def estimate_subtree_width(node)
        node_width = estimate_node_width(node)
        return node_width if node.children.empty?

        # Width is max of node width or sum of children widths
        children_width = node.children.sum { |c| estimate_subtree_width(c) }
        children_width += (node.children.size - 1) * NODE_HORIZONTAL_SPACING

        [node_width, children_width].max
      end

      # Calculates the total width of the entire tree
      #
      # @param root [Diagram::Mindmap::MindmapNode] root node
      # @return [Numeric] tree width
      def calculate_tree_width(root)
        estimate_subtree_width(root) + ROOT_PADDING * 2
      end

      # Builds connections between parent and child nodes
      #
      # @param node [Diagram::Mindmap::MindmapNode] current node
      # @param connections [Array<Hash>] accumulator
      # @return [Array<Hash>] all connections
      def build_connections(node, connections = [])
        node.children.each do |child|
          connections << {
            from: node.id,
            to: child.id,
            type: :parent_child
          }

          # Recursively build connections for children
          build_connections(child, connections)
        end

        connections
      end

      # Calculates the bounding box for all positioned nodes
      #
      # @param nodes [Array<Hash>] positioned nodes
      # @return [Hash] width and height
      def calculate_bounds(nodes)
        return { width: 0, height: 0 } if nodes.empty?

        max_x = nodes.map { |n| n[:x] + n[:width] / 2 }.max
        max_y = nodes.map { |n| n[:y] + n[:height] }.max

        {
          width: max_x + ROOT_PADDING,
          height: max_y + ROOT_PADDING
        }
      end
    end
  end
end