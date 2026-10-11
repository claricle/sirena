# frozen_string_literal: true

require_relative "base"
require_relative "mindmap_cose"
require_relative "mindmap_node_size"
require_relative "../notation/mermaid/ir_adapters/mindmap"

module Sirena
  module Layout
    # Transforms a Mindmap diagram into a positioned layout structure.
    #
    # Nodes are placed by the cose-bilkent force layout mmdc uses
    # (MindmapCose); edges are drawn centre to centre like mmdc's.
    #
    # @example Transform a mindmap
    #   transform = Layout::Mindmap.new
    #   layout = transform.to_graph(diagram)
    class Mindmap < Base
      # Space between the node bounding box and the canvas edge.
      PADDING = 10

      # Distance from a node's centre at which an edge starts or ends.
      EDGE_INSET = 15.0
      LABEL_LINE_PITCH = 1.2

      class LabelLine < Lutaml::Model::Serializable
        attribute :text, :string
        attribute :x, :float
        attribute :y, :float
      end

      class Label < Lutaml::Model::Serializable
        attribute :text, :string
        attribute :x, :float
        attribute :y, :float
        attribute :font_size, :float
        attribute :lines, LabelLine, collection: true, default: -> { [] }
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

        prepare_graph(graph)
        positioned_graph(graph)
      end

      private

      def prepare_graph(graph)
        @nodes_by_id = graph.nodes.to_h { |node| [node.id, node] }
        @levels = {}
        @sizes = {}
      end

      def positioned_graph(graph)
        positioned_nodes = position_nodes(graph)
        {
          nodes: positioned_nodes,
          connections: graph_connections(graph),
          **canvas_size(positioned_nodes),
          root: positioned_nodes.first,
        }
      end

      def graph_connections(graph)
        graph.edges.map do |edge|
          { from: edge.source_id, to: edge.target_id, type: edge.role.to_sym }
        end
      end

      def ir_graph(diagram)
        return diagram if diagram.is_a?(IR::Graph)

        Notation::Mermaid::IRAdapters::Mindmap.call(diagram)
      end

      def scene(diagram)
        graph = build_graph(diagram)
        nodes = typed_nodes(graph[:nodes])
        width = graph[:width]
        height = graph[:height]
        Scene.new(
          width: width, height: height,
          view_box: "0 0 #{width.to_f} #{height.to_f}",
          children: nodes,
          edges: typed_edges(graph[:connections], nodes)
        )
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
        center_x = node[:x]
        top_y = node[:y]
        radius = [width, height].max / 2
        { x: center_x - (width / 2), y: top_y, width: width, height: height,
          center_x: center_x, center_y: top_y + radius, radius: radius }
      end

      def node_label(node, geometry)
        lines = node[:lines]
        x = geometry[:center_x]
        y = label_baseline(node, geometry) - first_line_lift(lines)
        Label.new(text: lines.join("\n"), x: geometry[:center_x],
                  y: y, font_size: layout_font_size,
                  lines: positioned_label_lines(lines, x, y))
      end

      def positioned_label_lines(lines, label_x, first_y)
        lines.each_with_index.map do |line, index|
          text = index == lines.length - 1 ? line : "#{line} "
          LabelLine.new(text: text, x: label_x,
                        y: (first_y + (index * label_line_pitch)).round(4))
        end
      end

      def label_baseline(node, geometry)
        center_y = geometry[:y] + (geometry[:height] / 2)
        center_y = geometry[:y] + geometry[:radius] if node[:shape] == "circle"
        center_y + 5
      end

      # Lifts the first line so a stack of lines stays centred on the node.
      def first_line_lift(lines)
        (lines.length - 1) * label_line_pitch / 2
      end

      def label_line_pitch
        layout_font_size * LABEL_LINE_PITCH
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
        bends = [midpoint(start_point, end_point)]
        Edge.new(**edge_attributes(source, target, [start_point, end_point],
                                   bends, index))
      end

      # An edge runs along the line between the node centres, EDGE_INSET
      # short of each centre.
      def edge_points(source, target)
        from = [source.center_x, node_middle(source)]
        to = [target.center_x, node_middle(target)]
        [inset_point(from, to), inset_point(to, from)]
      end

      def node_middle(node)
        node.y + (node.height / 2)
      end

      def inset_point(from, toward)
        axes = from.zip(toward)
        distance = Math.hypot(*axes.map { |start, stop| stop - start })
        return Point.new(x: from[0], y: from[1]) if distance.zero?

        x, y = axes.map { |start, stop| inset(start, stop, distance) }
        Point.new(x: x, y: y)
      end

      # One coordinate of the point EDGE_INSET along the way to +toward+.
      def inset(from, toward, distance)
        from + ((toward - from) * EDGE_INSET / distance)
      end

      def midpoint(first, second)
        Point.new(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)
      end

      def edge_attributes(source, target, points, bends, index)
        start_point, end_point = points
        section = Section.new(
          start_point: start_point, end_point: end_point, bend_points: bends,
        )
        { id: "edge_#{index}", source: source.id, target: target.id,
          path: basis_path(start_point, bends.first, end_point),
          colour_level: source.level, sections: [section] }
      end

      # A uniform cubic B-spline through three points, as d3's curveBasis
      # draws it.
      def basis_path(first, middle, last)
        points = [first, middle, last]
        beginning = blend(points, [5, 1, 0])
        [
          "M #{first.x} #{first.y} L #{beginning}",
          "C #{blend(points, [2, 1, 0], 3)}, #{blend(points, [1, 2, 0], 3)}, " \
          "#{blend(points, [1, 4, 1])}",
          "C #{blend(points, [0, 2, 1], 3)}, #{blend(points, [0, 1, 2], 3)}, " \
          "#{blend(points, [0, 1, 5])}",
          "L #{last.x} #{last.y}",
        ].join(" ")
      end

      def blend(points, weights, divisor = 6)
        x = points.zip(weights).sum { |point, weight| point.x * weight }
        y = points.zip(weights).sum { |point, weight| point.y * weight }
        "#{x / divisor} #{y / divisor}"
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
          "Q #{near_left} #{top}, #{center_x} #{top} ",
          "Q #{near_right} #{top}, #{near_right} #{high} ",
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
          width: PADDING * 2,
          height: PADDING * 2,
          root: nil,
        }
      end

      # Places every node with the cose-bilkent layout, then frames the
      # result with PADDING.
      #
      # @param graph [IR::Graph] mindmap graph in depth-first order
      # @return [Array<Hash>] positioned nodes, x = centre, y = top
      def position_nodes(graph)
        centres = MindmapCose.call(cose_sizes(graph), cose_edges(graph))
        nodes = graph.nodes.map { |node| node_entry(node, centres[node.id]) }
        frame(nodes)
      end

      def cose_sizes(graph)
        graph.nodes.map do |node|
          size = node_size(node)
          [node.id, size[:width], size[:height]]
        end
      end

      def cose_edges(graph)
        graph.edges.map { |edge| [edge.source_id, edge.target_id] }
      end

      def node_entry(node, centre)
        size = node_size(node)
        { id: node.id, content: node.label, x: centre[0],
          y: centre[1] - (size[:height] / 2), width: size[:width],
          height: size[:height], lines: size[:lines],
          level: level_for(node), shape: node.role }
      end

      # Moves the nodes so their bounding box starts PADDING from the
      # canvas origin.
      def frame(nodes)
        left, top = top_left(nodes)
        nodes.map do |node|
          node.merge(x: node[:x] - left + PADDING, y: node[:y] - top + PADDING)
        end
      end

      def top_left(nodes)
        [nodes.map { |node| node[:x] - (node[:width] / 2) }.min,
         nodes.map { |node| node[:y] }.min]
      end

      # The mmdc box of a node: width, height and wrapped label lines.
      #
      # @param node [IR::Node] node
      # @return [Hash] :width, :height, :lines
      def node_size(node)
        @sizes[node.id] ||= MindmapNodeSize.call(
          node.label, node.role,
          font_size: layout_font_size, line_height: layout_line_height
        )
      end

      def layout_font_size
        positive_metric(theme.typography&.font_size_large) ||
          MindmapNodeSize::FONT_SIZE.to_f
      end

      def layout_line_height
        positive_metric(theme.typography&.line_height) ||
          MindmapNodeSize::LINE_HEIGHT_RATIO
      end

      def positive_metric(value)
        value if value.is_a?(Numeric) && value.finite? && value.positive?
      end

      def level_for(node)
        @levels[node.id] ||= begin
          parent = @nodes_by_id[node.parent_id]
          parent ? level_for(parent) + 1 : 0
        end
      end

      # The canvas: the node bounding box plus PADDING on every side.
      #
      # @param nodes [Array<Hash>] framed nodes
      # @return [Hash] :width and :height
      def canvas_size(nodes)
        right = nodes.map { |node| node[:x] + (node[:width] / 2) }.max
        bottom = nodes.map { |node| node[:y] + node[:height] }.max
        { width: right + PADDING, height: bottom + PADDING }
      end
    end
  end
end
