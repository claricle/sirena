# frozen_string_literal: true

require_relative "base"
require_relative "../notation/mermaid/ir_adapters/mindmap"

module Sirena
  module Layout
    # Transforms a Mindmap diagram into a positioned layout structure.
    #
    # The layout algorithm handles:
    # - Tree-based layout with root at center
    # - Radial positioning of branches
    # - Level-based spacing
    # - Connection path calculation
    #
    # @example Transform a mindmap
    #   transform = Layout::Mindmap.new
    #   layout = transform.to_graph(diagram)
    class Mindmap < Base
      PADDING = 40

      # Horizontal spacing between sibling nodes
      NODE_HORIZONTAL_SPACING = 120

      # Vertical spacing between levels
      LEVEL_VERTICAL_SPACING = 80

      # Default node dimensions
      DEFAULT_NODE_WIDTH = 100
      DEFAULT_NODE_HEIGHT = 40

      # Padding for root node
      ROOT_PADDING = 20

      class Label < Lutaml::Model::Serializable
        attribute :text, :string
        attribute :x, :float
        attribute :y, :float
      end

      class Node < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :x, :float
        attribute :y, :float
        attribute :width, :float
        attribute :height, :float
        attribute :center_x, :float
        attribute :center_y, :float
        attribute :radius, :float
        attribute :level, :integer
        attribute :shape, :string
        attribute :shape_points, :string
        attribute :shape_path, :string
        attribute :labels, Label, collection: true, default: -> { [] }
      end

      class Point < Lutaml::Model::Serializable
        attribute :x, :float
        attribute :y, :float
      end

      class Section < Lutaml::Model::Serializable
        attribute :start_point, Point
        attribute :end_point, Point
        attribute :bend_points, Point, collection: true, default: -> { [] }
      end

      class Edge < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :source, :string
        attribute :target, :string
        attribute :path, :string
        attribute :colour_level, :integer
        attribute :sections, Section, collection: true, default: -> { [] }
      end

      class Scene < Layout::Scene
        attribute :view_box, :string
        attribute :children, Node, collection: true, default: -> { [] }
        attribute :edges, Edge, collection: true, default: -> { [] }
      end

      # Transforms the diagram into a layout structure.
      #
      # @param diagram [Diagram::Mindmap] the mindmap diagram
      # @return [Hash] layout data with nodes and connections
      def build_graph(diagram)
        graph = ir_graph(diagram)
        root = graph.nodes.find { |node| node.parent_id.nil? }
        return empty_graph unless root

        @children_by_parent = graph.nodes.group_by(&:parent_id)
        @nodes_by_id = graph.nodes.to_h { |node| [node.id, node] }
        @levels = {}

        # Position nodes using tree layout
        positioned_nodes = position_tree(root)

        # Build connections between nodes
        connections = graph.edges.map do |edge|
          { from: edge.source_id, to: edge.target_id, type: edge.role.to_sym }
        end

        # Calculate bounds
        bounds = calculate_bounds(positioned_nodes)

        {
          nodes: positioned_nodes,
          connections: connections,
          width: bounds[:width],
          height: bounds[:height],
          root: positioned_nodes.first,
        }
      end

      private

      def ir_graph(diagram)
        return diagram if diagram.is_a?(IR::Graph)

        Notation::Mermaid::IRAdapters::Mindmap.call(diagram)
      end

      def scene(diagram)
        graph = build_graph(diagram)
        nodes = typed_nodes(graph[:nodes])
        width, height = canvas_dimensions(graph)
        Scene.new(
          width: width, height: height,
          view_box: "0 0 #{width.to_f} #{height.to_f}",
          children: nodes,
          edges: typed_edges(graph[:connections], nodes)
        )
      end

      def canvas_dimensions(graph)
        [graph[:width] + (PADDING * 2), graph[:height] + (PADDING * 2)]
      end

      def typed_nodes(nodes)
        nodes.map { |node| typed_node(node) }
      end

      def typed_node(node)
        geometry = node_geometry(node)
        Node.new(
          id: node[:id], level: node[:level], shape: node[:shape],
          **geometry, **node_shape_geometry(geometry),
          labels: [node_label(node, geometry)]
        )
      end

      def node_shape_geometry(geometry)
        coordinates = {
          center_x: geometry[:center_x], top_y: geometry[:y],
          width: geometry[:width], height: geometry[:height]
        }
        { shape_points: hexagon_points(**coordinates),
          shape_path: cloud_path(**coordinates) }
      end

      def node_geometry(node)
        width = node[:width]
        height = node[:height]
        center_x = node[:x] + PADDING
        top_y = node[:y] + PADDING
        radius = [width, height].max / 2
        { x: center_x - (width / 2), y: top_y, width: width, height: height,
          center_x: center_x, center_y: top_y + radius, radius: radius }
      end

      def node_label(node, geometry)
        center_y = geometry[:y] + (geometry[:height] / 2)
        center_y = geometry[:y] + geometry[:radius] if node[:shape] == "circle"
        Label.new(text: node[:content], x: geometry[:center_x], y: center_y + 5)
      end

      def typed_edges(connections, nodes)
        nodes_by_id = nodes.to_h { |node| [node.id, node] }
        connections.filter_map.with_index do |connection, index|
          typed_edge(connection, nodes_by_id, index)
        end
      end

      def typed_edge(connection, nodes, index)
        source = nodes[connection[:from]]
        target = nodes[connection[:to]]
        return unless source && target

        start_point, end_point = edge_points(source, target)
        bends = edge_bends(start_point, end_point)
        Edge.new(**edge_attributes(source, target, [start_point, end_point],
                                   bends, index))
      end

      def edge_points(source, target)
        start_point = Point.new(
          x: source.center_x, y: source.y + (source.height / 2),
        )
        [start_point, Point.new(x: target.center_x, y: target.y)]
      end

      def edge_bends(start_point, end_point)
        control_y = start_point.y + ((end_point.y - start_point.y) / 2)
        [Point.new(x: start_point.x, y: control_y),
         Point.new(x: end_point.x, y: control_y)]
      end

      def edge_attributes(source, target, points, bends, index)
        start_point, end_point = points
        section = Section.new(
          start_point: start_point, end_point: end_point, bend_points: bends,
        )
        { id: "edge_#{index}", source: source.id, target: target.id,
          path: bezier_path(start_point, bends, end_point),
          colour_level: source.level, sections: [section] }
      end

      def bezier_path(start_point, bends, end_point)
        "M #{start_point.x} #{start_point.y} " \
          "C #{bends[0].x} #{bends[0].y}, " \
          "#{bends[1].x} #{bends[1].y}, " \
          "#{end_point.x} #{end_point.y}"
      end

      def hexagon_points(center_x:, top_y:, width:, height:)
        hexagon_vertices(center_x, top_y, width, height)
          .map { |point| point.join(",") }.join(" ")
      end

      def hexagon_vertices(center_x, top_y, width, height)
        offset = width * 0.2
        left = center_x - (width / 2)
        right = center_x + (width / 2)
        middle_y = top_y + (height / 2)
        bottom_y = top_y + height
        [[left + offset, top_y], [right - offset, top_y], [right, middle_y],
         [right - offset, bottom_y], [left + offset, bottom_y],
         [left, middle_y]]
      end

      def cloud_path(center_x:, top_y:, width:, height:)
        left, inner_left, near_left, near_right, inner_right, right =
          cloud_x_positions(center_x, width)
        top, high, upper, shoulder, lower, bottom =
          cloud_y_positions(top_y, height)
        [
          "M #{left} #{lower} Q #{left} #{shoulder}, #{inner_left} #{upper} ",
          "Q #{inner_left} #{top}, #{near_left} #{high} ",
          "Q #{center_x} #{top}, #{near_right} #{high} ",
          "Q #{inner_right} #{top}, #{inner_right} #{upper} ",
          "Q #{right} #{shoulder}, #{right} #{lower} ",
          "Q #{right} #{bottom}, #{center_x} #{bottom} ",
          "Q #{left} #{bottom}, #{left} #{lower} Z",
        ].join
      end

      def cloud_x_positions(center_x, width)
        half_width = width / 2
        [center_x - half_width, center_x - (half_width * 0.6),
         center_x - (half_width * 0.2), center_x + (half_width * 0.2),
         center_x + (half_width * 0.6), center_x + half_width]
      end

      def cloud_y_positions(top_y, height)
        [top_y, top_y + (height * 0.1), top_y + (height * 0.2),
         top_y + (height * 0.3), top_y + (height * 0.6), top_y + height]
      end

      def empty_graph
        {
          nodes: [],
          connections: [],
          width: 0,
          height: 0,
          root: nil,
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
          content: root.label,
          x: root_x,
          y: ROOT_PADDING,
          width: root_width,
          height: root_height,
          level: level_for(root),
          shape: root.role,
        }

        # Position children recursively
        if children_of(root).any?
          position_children(
            root,
            root_x,
            ROOT_PADDING + root_height + LEVEL_VERTICAL_SPACING,
            nodes,
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
        children = children_of(parent)
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
            content: child.label,
            x: node_x,
            y: y,
            width: child_width,
            height: child_height,
            level: level_for(child),
            shape: child.role,
            parent_id: parent.id,
          }

          # Recursively position grandchildren
          if children_of(child).any?
            position_children(
              child,
              node_x,
              y + child_height + LEVEL_VERTICAL_SPACING,
              nodes,
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
        measured = measure_text(node.label.to_s, font_size: node_font_size)
        base_width = [measured[:width] + 20, DEFAULT_NODE_WIDTH].max

        # Adjust for shape
        case node.role
        when "circle", "hexagon"
          base_width * 1.2
        else
          base_width
        end
      end

      def node_font_size
        theme.typography&.font_size_small ||
          Theme::Registry.get(:default).typography.font_size_small
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
        children = children_of(node)
        return node_width if children.empty?

        # Width is max of node width or sum of children widths
        children_width = children.sum { |child| estimate_subtree_width(child) }
        children_width += (children.size - 1) * NODE_HORIZONTAL_SPACING

        [node_width, children_width].max
      end

      # Calculates the total width of the entire tree
      #
      # @param root [Diagram::Mindmap::MindmapNode] root node
      # @return [Numeric] tree width
      def calculate_tree_width(root)
        estimate_subtree_width(root) + ROOT_PADDING * 2
      end

      def children_of(node)
        @children_by_parent.fetch(node.id, [])
      end

      def level_for(node)
        @levels[node.id] ||= begin
          parent = @nodes_by_id[node.parent_id]
          parent ? level_for(parent) + 1 : 0
        end
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
          height: max_y + ROOT_PADDING,
        }
      end
    end
  end
end
