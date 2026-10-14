# frozen_string_literal: true

require_relative "base"
require_relative "flowchart/directed_placement"
require_relative "flowchart/edge_router"
require_relative "flowchart/label_backdrop_geometry"
require_relative "elk_placement"
require_relative "../diagram/flowchart"
require_relative "../diagram/flowchart_label_text"
require_relative "../notation/mermaid/ir_adapters/flowchart"

module Sirena
  module Layout
    # Computes final canvas geometry for flowcharts.
    class Flowchart < Base
      # mmdc draws every flowchart text, node, cluster title and edge
      # label alike, at 16px; a theme overrides it with flowchart_font_size.
      DEFAULT_FONT_SIZE = 16.0
      NODE_LINE_HEIGHT = 1.5
      MIDDLE_BASELINE_EMS = 0.35

      # The size every flowchart text is measured and drawn at. A theme
      # value that is not a positive finite number falls back to the
      # default: a NaN raises inside the box arithmetic and a non-positive
      # one produces a negative SVG width.
      def self.font_size(theme)
        value = theme&.typography&.flowchart_font_size
        usable = value.is_a?(Numeric) && value.finite? && value.positive?
        usable ? value : DEFAULT_FONT_SIZE
      end

      # What mmdc adds to the label, measured on its output, as
      # [width, height]. A shape not listed is sized as a box.
      SHAPE_PADDING = {
        "rounded" => [30.0, 30.0],
        "asymmetric" => [24.75, 15.0],
        "hexagon" => [45.0, 15.0],
        "parallelogram" => [60.0, 15.0],
        "parallelogram_alt" => [60.0, 15.0],
        "trapezoid" => [60.0, 15.0],
        "trapezoid_alt" => [60.0, 15.0],
      }.freeze
      BOX_PADDING = [60.0, 30.0].freeze
      # An inferred node whose id is later reused by an empty subgraph keeps
      # the node in mmdc, but receives its smaller collision-placeholder box.
      COLLISION_NODE_PADDING = [32.0, 16.0].freeze
      # A hexagon grows wider with each line under the first: 45 for one
      # line, 48.15 for two in mmdc's output, so 0.118 a pixel of height.
      HEXAGON_WIDTH_PER_HEIGHT = 0.118
      # Square shapes: a rhombus is label width + label height + 30 on a
      # side; a circle is label width + 15 across (25 for a double one).
      CIRCLE_PADDING = { "circle" => 15.0, "double_circle" => 25.0 }.freeze
      RHOMBUS_PADDING = 30.0

      CLUSTER_CORNER = FlowchartEdgeRouter::CLUSTER_CORNER
      ROUNDED_CORNER = 5.0
      CLUSTER_TITLE_BASELINE = 20
      EDGE_LABEL_LIFT = 5.0
      # mmdc breaks an edge label wider than this at spaces, and the label
      # box takes this width. One word wider than it stays on its line.
      EDGE_LABEL_WRAP_WIDTH = 200.0
      SUBSTITUTE_FONT_HEADROOM = 1.2
      ICON_ADVANCE_EMS = 1.3
      SOURCE_ELK_PLACEMENT = :mermaid_elk
      SOURCE_ELK_SPACING = 35
      private_constant :SOURCE_ELK_PLACEMENT, :SOURCE_ELK_SPACING

      SELF_LOOP_DEPTH = 0.45
      SELF_LOOP_HALF_SPAN = 0.175
      SELF_LOOP_HALF_SPAN_LIMITS = (18.0..50.0)
      SELF_LOOP_MAX_DEPTH = 48.0
      SELF_LOOP_SIDES = {
        "DOWN" => [0, 1].freeze,
        "UP" => [0, -1].freeze,
        "RIGHT" => [1, 0].freeze,
        "LEFT" => [-1, 0].freeze,
      }.freeze

      NODE_OUTLINES = {
        "rounded" => "rounded", "stadium" => "stadium",
        "circle" => "circle", "double_circle" => "circle",
        "rhombus" => "rhombus", "hexagon" => "hexagon"
      }.freeze

      BOUNDARY_SCALES = {
        "rhombus" => :rhombus_scale, "circle" => :circle_scale,
        "hexagon" => :hexagon_scale, "rounded" => :rounded_scale,
        "stadium" => :stadium_scale
      }.freeze
      private_constant :BOUNDARY_SCALES

      EDGE_HEADS = {
        "arrow" => "arrow", "cross" => "cross", "circle" => "circle"
      }.freeze
      ARROW_LENGTH = 8.0
      ARROW_HALF_WIDTH = 4.0
      CIRCLE_HEAD_RADIUS = 5.5
      CROSS_HEAD_HALF = 4.5
      CIRCLE_HEAD_REACH = 6.6
      CROSS_HEAD_REACH = 6.5

      class Point < Lutaml::Model::Serializable
        attribute :x, :float
        attribute :y, :float
      end

      class TextRun < Lutaml::Model::Serializable
        attribute :content, :string
        attribute :x, :float
        attribute :y, :float
      end

      class Label < Lutaml::Model::Serializable
        attribute :text, :string
        attribute :width, :float
        attribute :height, :float
        attribute :x, :float
        attribute :y, :float
        attribute :text_y, :float
        attribute :font_size, :float
        attribute :lines, :string, collection: true, default: -> { [] }
        attribute :line_ys, :float, collection: true, default: -> { [] }
        attribute :runs, TextRun, collection: true, default: -> { [] }

        def backdrop_geometry(font_size:)
          LabelBackdropGeometry.for_label(self, font_size: font_size)
        end

        alias assign_line_ys line_ys=
        private :assign_line_ys

        def line_ys=(values)
          assign_line_ys(values)
          return unless defined?(@runs) && runs.any?

          self.text_y = line_ys.first || y
          runs.each_with_index do |run, row|
            run.y = row.zero? ? nil : line_ys.fetch(row, nil)
          end
        end
      end

      class Line < Lutaml::Model::Serializable
        attribute :x1, :float
        attribute :y1, :float
        attribute :x2, :float
        attribute :y2, :float
      end

      class Head < Lutaml::Model::Serializable
        attribute :shape, :string
        attribute :points, :string
        attribute :x, :float
        attribute :y, :float
        attribute :radius, :float
        attribute :lines, Line, collection: true, default: -> { [] }
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
        attribute :sections, Section, collection: true, default: -> { [] }
        attribute :labels, Label, collection: true, default: -> { [] }
        attribute :arrow_type, :string
        attribute :path, :string
        attribute :heads, Head, collection: true, default: -> { [] }
      end

      class Node < Lutaml::Model::Serializable
        attribute :fill, :string
        attribute :stroke, :string
        attribute :id, :string
        attribute :x, :float
        attribute :y, :float
        attribute :width, :float
        attribute :height, :float
        attribute :labels, Label, collection: true, default: -> { [] }
        attribute :shape, :string
        attribute :shape_kind, :string
        attribute :shape_points, :string
        attribute :shape_x, :float
        attribute :shape_y, :float
        attribute :shape_width, :float
        attribute :shape_height, :float
        attribute :center_x, :float
        attribute :center_y, :float
        attribute :radius, :float
        attribute :corner_radius, :float
        attribute :cluster, :boolean, default: false
        attribute :container, :boolean, default: false
        attribute :children, Node, collection: true, default: -> { [] }
      end

      class Scene < Layout::Scene
        attribute :id, :string
        attribute :view_box, :string
        attribute :children, Node, collection: true, default: -> { [] }
        attribute :edges, Edge, collection: true, default: -> { [] }
      end

      # Builds a typed Scene from a hand-positioned ELK-shaped graph. This is
      # useful for geometry specs and for the eventual elkrb adapter: the Hash
      # stays inside Layout and never reaches Renderer.
      def self.from_graph(graph, theme: nil)
        layout = new
        layout.theme = theme if theme
        layout.send(:scene_from_graph, graph)
      end

      # Engine#choose_placement sets this for layout_engine: :elk. Explicit
      # callers retain the dagre-compatible orchestration below.
      attr_accessor :placement

      def source_placement=(value)
        self.placement = value == :elk ? SOURCE_ELK_PLACEMENT : value
      end

      def scene(diagram)
        graph = build_graph(ir_graph(diagram))
        place_graph(graph)
        compact_collision_nodes(graph[:children])
        scene_from_graph(graph)
      end

      private

      def place_graph(graph)
        unless placement == SOURCE_ELK_PLACEMENT
          return DirectedPlacement.apply(graph, center_edge_labels: true)
        end

        graph[:layoutOptions][ElkOptions::NODE_NODE_SPACING] =
          SOURCE_ELK_SPACING
        graph[:layoutOptions][ElkOptions::LAYER_SPACING] = SOURCE_ELK_SPACING
        ElkPlacement.apply(graph)
      end

      def ir_graph(diagram)
        return diagram if diagram.is_a?(IR::Graph)

        Notation::Mermaid::IRAdapters::Flowchart.call(diagram)
      end

      # Builds the temporary ELK-shaped input used within this layout.
      def build_graph(graph)
        {
          id: diagram_identifier(graph),
          children: transform_children(graph),
          edges: transform_edges(graph),
          layoutOptions: layout_options(graph),
        }
      end

      def scene_from_graph(graph)
        flat = flatten(graph)
        flat[:label_endpoints] = label_endpoints(graph, flat[:clusters])
        dx, dy = self_loop_overflow(flat)
        page = shift_page(flat, dx, dy)
        edges = typed_edges(page)

        Scene.new(id: graph[:id] || "flowchart", **canvas_geometry(page, edges),
                  children: typed_children(
                    graph[:children] || [], 0, 0, dx, dy
                  ),
                  edges: edges)
      end

      def canvas_geometry(page, edges)
        width, height = canvas_size(page, edges)
        { width: width, height: height, view_box: "0 0 #{width} #{height}" }
      end

      # [width, height] of the boxes and of every routed edge, so a route
      # that detours round a box stays on the page.
      def canvas_size(page, edges)
        [[calculate_width(page), route_reach(edges, :x)].max,
         [calculate_height(page), route_reach(edges, :y)].max]
      end

      # How far a routed edge reaches along :x or :y, plus the page margin.
      def route_reach(edges, axis)
        points = edges.flat_map do |edge|
          edge.sections.flat_map do |section|
            [section.start_point, *section.bend_points, section.end_point]
          end
        end
        (points.map { |point| point.public_send(axis) }.max || 0) +
          DirectedPlacement::PAGE_MARGIN
      end

      def flatten(graph)
        clusters = []
        nodes = []
        collect(graph[:children] || [], 0, 0, clusters, nodes)
        graph.merge(children: nodes, clusters: clusters)
      end

      def collect(children, delta_x, delta_y, clusters, nodes)
        children.each do |child|
          placed = shifted_box(child, delta_x, delta_y)
          unless child[:children]
            nodes << placed
            next
          end

          clusters << placed.except(:children) if cluster?(child)
          collect(child[:children], placed[:x], placed[:y], clusters, nodes)
        end
      end

      def shifted_box(box, delta_x, delta_y)
        box.merge(x: (box[:x] || 0) + delta_x,
                  y: (box[:y] || 0) + delta_y)
      end

      def cluster?(child)
        FlowchartEdgeRouter.cluster?(child)
      end

      def shift_page(graph, delta_x, delta_y)
        return graph if delta_x.zero? && delta_y.zero?

        graph.merge(children: shift_boxes(graph[:children], delta_x, delta_y),
                    clusters: shift_boxes(graph[:clusters], delta_x, delta_y),
                    edges: shift_edges(graph[:edges], delta_x, delta_y))
      end

      def shift_boxes(boxes, delta_x, delta_y)
        (boxes || []).map { |box| shifted_box(box, delta_x, delta_y) }
      end

      def shift_edges(edges, delta_x, delta_y)
        (edges || []).map { |edge| shifted_edge(edge, delta_x, delta_y) }
      end

      def shifted_edge(edge, delta_x, delta_y)
        sections = edge[:sections]
        return edge unless sections&.any?

        edge.merge(sections: sections.map do |section|
          shifted_section(section, delta_x, delta_y)
        end)
      end

      def shifted_section(section, delta_x, delta_y)
        bends = section[:bendPoints]
        return section unless bends&.any?

        section.merge(bendPoints: shift_boxes(bends, delta_x, delta_y))
      end

      def typed_children(children, parent_x, parent_y, delta_x, delta_y)
        children.map do |child|
          x = (child[:x] || 0) + parent_x + delta_x
          y = (child[:y] || 0) + parent_y + delta_y
          typed_node(child, x, y, delta_x, delta_y)
        end
      end

      def typed_node(node, x_pos, y_pos, delta_x, delta_y)
        bounds = { x: x_pos, y: y_pos, width: node[:width] || 100,
                   height: node[:height] || 50 }
        Node.new(**typed_node_attributes(node, bounds),
                 children: typed_children(
                   node[:children] || [], x_pos - delta_x, y_pos - delta_y,
                   delta_x, delta_y
                 ))
      end

      def typed_node_attributes(node, bounds)
        is_cluster = cluster?(node)
        shape = node.dig(:metadata, :shape) || "rect"
        kind = is_cluster ? "cluster" : (NODE_OUTLINES[shape] || "rect")
        { id: node[:id], **bounds, shape: shape, shape_kind: kind,
          fill: node.dig(:metadata, :fill),
          stroke: node.dig(:metadata, :stroke),
          labels: typed_node_labels(node, bounds, is_cluster),
          **shape_geometry(kind, bounds), **painted_box(bounds, is_cluster),
          cluster: is_cluster, container: node.key?(:children) }
      end

      def shape_geometry(kind, bounds)
        x, y, width, height = bounds.values_at(:x, :y, :width, :height)
        { shape_points: polygon_points(kind, x, y, width, height),
          center_x: x + (width / 2.0), center_y: y + (height / 2.0),
          radius: [width, height].min / 2.0,
          corner_radius: corner_radius(kind, width, height) }
      end

      def painted_box(bounds, cluster)
        drawn = cluster ? bounds.transform_values(&:to_i) : bounds
        { shape_x: drawn[:x], shape_y: drawn[:y],
          shape_width: drawn[:width], shape_height: drawn[:height] }
      end

      def typed_node_labels(node, bounds, cluster)
        (node[:labels] || []).first(1).map do |label|
          x, y = node_label_anchor(bounds, cluster)
          y = cluster_title_y(node, bounds, label) if cluster
          Label.new(
            text: label[:text], width: label[:width], height: label[:height],
            x: x, y: y, **label_geometry(label, x, y, with_runs: !cluster)
          )
        end
      end

      def node_label_anchor(bounds, cluster)
        x, y, width, height = bounds.values_at(:x, :y, :width, :height)
        label_y = y + (cluster ? CLUSTER_TITLE_BASELINE : height / 2.0)
        label_x = cluster ? x + (width.to_i / 2) : x + (width / 2.0)
        [label_x, label_y]
      end

      # Keep a title inside the reserved header, rather than over its first
      # child. Ordinary headers retain their established label position.
      def cluster_title_y(node, bounds, label)
        header = cluster_header_height(node, bounds)
        half = label[:height].to_f / 2.0
        center = CLUSTER_TITLE_BASELINE.to_f
        center = header / 2.0 if center <= half || center + half >= header
        bounds[:y] + center
      end

      def cluster_header_height(node, bounds)
        (node[:children] || []).filter_map { |child| child[:y] }.min ||
          bounds[:height]
      end

      def label_geometry(label, x_pos, y_pos, with_runs: false)
        lines = label[:text].to_s.scrub.split("\n", -1)
        lines = lines.one? ? [] : sentence_lines(lines)
        font_size = layout_font_size
        line_ys = line_baselines(y_pos, label[:height], lines, font_size)
        text_y = line_ys.first || y_pos
        runs = with_runs ? text_runs(lines, line_ys, x_pos) : []
        { font_size: font_size, lines: lines, line_ys: line_ys,
          text_y: text_y, runs: runs }
      end

      def text_runs(lines, baselines, x_pos)
        lines.each_with_index.map do |line, row|
          TextRun.new(
            content: line,
            x: x_pos,
            y: row.zero? ? nil : baselines.fetch(row),
          )
        end
      end

      def sentence_lines(lines)
        lines[0...-1].map { |line| "#{line} " } << lines.last
      end

      def line_baselines(y_pos, height, lines, font_size)
        return [] if lines.empty?

        pitch = height / lines.size
        first = y_pos - (pitch * (lines.size - 1) / 2.0) +
          (MIDDLE_BASELINE_EMS * font_size)
        lines.each_index.map { |row| first + (row * pitch) }
      end

      def polygon_points(kind, x_pos, y_pos, width, height)
        case kind
        when "rhombus"
          format_polygon(rhombus_points(x_pos, y_pos, width, height))
        when "hexagon"
          format_polygon(hexagon_points(x_pos, y_pos, width, height))
        end
      end

      def format_polygon(points)
        points.map { |x, y| "#{x},#{y}" }.join(" ")
      end

      def rhombus_points(x_pos, y_pos, width, height)
        cx = x_pos + (width / 2.0)
        cy = y_pos + (height / 2.0)
        [[cx, y_pos], [x_pos + width, cy], [cx, y_pos + height], [x_pos, cy]]
      end

      def hexagon_points(x_pos, y_pos, width, height)
        left, inner_left, inner_right, right = hexagon_xs(x_pos, width)
        middle = y_pos + (height / 2.0)
        bottom = y_pos + height
        [[inner_left, y_pos], [inner_right, y_pos], [right, middle],
         [inner_right, bottom], [inner_left, bottom], [left, middle]]
      end

      def hexagon_xs(x_pos, width)
        quarter = width / 4.0
        [x_pos, x_pos + quarter, x_pos + width - quarter, x_pos + width]
      end

      def corner_radius(kind, width, height)
        return CLUSTER_CORNER if kind == "cluster"
        return ROUNDED_CORNER if kind == "rounded"
        return [width, height].min / 2.0 if kind == "stadium"

        0.0
      end

      def typed_edges(graph)
        (graph[:edges] || []).filter_map { |edge| typed_edge(edge, graph) }
      end

      def typed_edge(edge, graph)
        source = find_endpoint(graph, edge[:sources]&.first)
        target = find_endpoint(graph, edge[:targets]&.first)
        return unless source && target

        Edge.new(**typed_edge_attributes(edge, graph, source, target))
      end

      def typed_edge_attributes(edge, graph, source, target)
        route, bends, label_route = edge_route(edge, graph, source, target)
        label_route = external_label_route(edge, graph, label_route)
        type = edge.dig(:metadata, :arrow_type).to_s
        { id: edge[:id], source: source[:id], target: target[:id],
          sections: [typed_section(route, bends)],
          labels: typed_edge_labels(edge, source, target, bends, label_route),
          arrow_type: type, path: edge_path(route, bends),
          heads: typed_heads(route, bends, source, target, type) }
      end

      # A crossing edge's label belongs between the boxes at its layout
      # level: the enclosing cluster and the outside node, not an interior
      # node's clipped outline. Keep the actual arrow route unchanged.
      def label_endpoints(graph, clusters)
        levels = LevelEdges.new(graph)
        containers = [nil, *clusters.map { |cluster| cluster[:id] }]
        entries = containers.flat_map { |container| levels.at(container) }
        entries.to_h do |edge, from, to|
          [edge[:id], [from, to]]
        end
      end

      def external_label_route(edge, graph, ordinary)
        ids = crossing_label_ids(edge, graph)
        return ordinary unless ids

        source, target = ids.map { |id| find_endpoint(graph, id) }
        return ordinary unless source && target

        edge_router.route(source, target, []).last
      end

      def crossing_label_ids(edge, graph)
        ids = graph.fetch(:label_endpoints, {})[edge[:id]]
        return unless ids&.all?
        return if ids == [edge[:sources]&.first, edge[:targets]&.first]

        ids
      end

      def typed_section(route, bends)
        Section.new(
          start_point: Point.new(x: route[0], y: route[1]),
          end_point: Point.new(x: route[2], y: route[3]),
          bend_points: bends.map do |point|
            Point.new(x: point[:x], y: point[:y])
          end,
        )
      end

      def typed_edge_labels(edge, source, target, bends, route)
        (edge[:labels] || []).first(1).map do |label|
          x, y = edge_label_anchor(source, target, bends, route)
          Label.new(
            text: label[:text], width: label[:width], height: label[:height],
            x: x, y: y, **label_geometry(label, x, y)
          )
        end
      end

      def edge_path(route, bends)
        sx, sy, tx, ty = route.map { |coordinate| coordinate.round(2) }
        return "M #{sx} #{sy} L #{tx} #{ty}" if bends.empty?

        (["M #{sx} #{sy}"] + bends.map do |point|
          "L #{point[:x].round(1)} #{point[:y].round(1)}"
        end + ["L #{tx} #{ty}"]).join(" ")
      end

      def typed_heads(route, bends, source, target, type)
        head_type = type.sub(/\A(?:thick|dotted)_/, "").delete_suffix("_both")
        shape = EDGE_HEADS[head_type]
        return [] unless shape

        ends = type.end_with?("_both") ? %i[source target] : [:target]
        ends.map do |which|
          geometry = head_tip_geometry(route, bends, source, target, which)
          typed_head(shape, geometry)
        end
      end

      def typed_head(shape, geometry)
        case shape
        when "cross" then cross_head(geometry)
        when "circle" then circle_head(geometry)
        else arrow_head(geometry)
        end
      end

      def arrow_head(geometry)
        Head.new(shape: "arrow", points: arrow_head_points(geometry))
      end

      def arrow_head_points(geometry)
        tip_x, tip_y, along_x, along_y, back_x, back_y = arrow_back(geometry)
        points = [[tip_x, tip_y],
                  [back_x - (along_y * ARROW_HALF_WIDTH),
                   back_y + (along_x * ARROW_HALF_WIDTH)],
                  [back_x + (along_y * ARROW_HALF_WIDTH),
                   back_y - (along_x * ARROW_HALF_WIDTH)]]
        format_head_points(points)
      end

      def format_head_points(points)
        points.map { |x, y| "#{x.round(1)},#{y.round(1)}" }.join(" ")
      end

      def arrow_back(geometry)
        tip_x, tip_y, from_x, from_y =
          geometry.values_at(:tip_x, :tip_y, :from_x, :from_y)
        along_x, along_y = unit_towards(tip_x, tip_y, from_x, from_y)
        back_x = tip_x + (along_x * ARROW_LENGTH)
        back_y = tip_y + (along_y * ARROW_LENGTH)
        [tip_x, tip_y, along_x, along_y, back_x, back_y]
      end

      def circle_head(geometry)
        x, y = backed_off(geometry, CIRCLE_HEAD_REACH)
        Head.new(shape: "circle", x: x.round(1), y: y.round(1),
                 radius: CIRCLE_HEAD_RADIUS)
      end

      def cross_head(geometry)
        tip_x, tip_y, arm_x, arm_y = cross_arms(geometry)
        lines = [[arm_x, arm_y], [arm_y, -arm_x]].map do |line_x, line_y|
          cross_line(tip_x, tip_y, line_x, line_y)
        end
        Head.new(shape: "cross", lines: lines)
      end

      def cross_arms(geometry)
        tip_x, tip_y = backed_off(geometry, CROSS_HEAD_REACH)
        along_x, along_y = cross_direction(geometry, tip_x, tip_y)
        arm_x = (along_x - along_y) * CROSS_HEAD_HALF
        arm_y = (along_y + along_x) * CROSS_HEAD_HALF
        [tip_x, tip_y, arm_x, arm_y]
      end

      def cross_direction(geometry, tip_x, tip_y)
        from_x, from_y = geometry.values_at(:from_x, :from_y)
        x, y = unit_towards(tip_x, tip_y, from_x, from_y)
        x = 1.0 if x.zero? && y.zero?
        [x, y]
      end

      def cross_line(tip_x, tip_y, line_x, line_y)
        Line.new(x1: (tip_x - line_x).round(1), y1: (tip_y - line_y).round(1),
                 x2: (tip_x + line_x).round(1), y2: (tip_y + line_y).round(1))
      end

      def backed_off(geometry, reach)
        tip_x, tip_y, from_x, from_y =
          geometry.values_at(:tip_x, :tip_y, :from_x, :from_y)
        along_x, along_y = unit_towards(tip_x, tip_y, from_x, from_y)
        [tip_x + (along_x * reach), tip_y + (along_y * reach)]
      end

      def unit_towards(tip_x, tip_y, from_x, from_y)
        span = Math.hypot(from_x - tip_x, from_y - tip_y)
        return [0.0, 0.0] if span.zero?

        [(from_x - tip_x) / span, (from_y - tip_y) / span]
      end

      def calculate_width(graph)
        boxes = drawn(graph)
        return DirectedPlacement::PAGE_MARGIN * 2 if boxes.empty?

        max_x = boxes.map { |node| (node[:x] || 0) + (node[:width] || 100) }.max
        [max_x, self_loop_reach(graph)[0]].max + DirectedPlacement::PAGE_MARGIN
      end

      def calculate_height(graph)
        boxes = drawn(graph)
        return DirectedPlacement::PAGE_MARGIN * 2 if boxes.empty?

        max_y = boxes.map { |node| (node[:y] || 0) + (node[:height] || 50) }.max
        [max_y, self_loop_reach(graph)[1]].max + DirectedPlacement::PAGE_MARGIN
      end

      def drawn(graph)
        (graph[:children] || []) + (graph[:clusters] || [])
      end

      def self_loop_bounds(graph)
        side = self_loop_side(graph)
        (graph[:edges] || []).reduce(nil) do |bounds, edge|
          node = self_loop_node(graph, edge)
          next bounds unless node

          extent = loop_edge_bounds(edge, node, side)
          merge_bounds(
            bounds, *extent.values_at(:min_x, :max_x, :min_y, :max_y)
          )
        end
      end

      def loop_edge_bounds(edge, node, side)
        bends = edge_bends(edge, node, node, side)
        bounds = loop_label_bounds(edge, node, bends)
        min_x, max_x = loop_axis_extent(bends, bounds, :x)
        min_y, max_y = loop_axis_extent(bends, bounds, :y)
        { min_x: min_x, max_x: max_x, min_y: min_y, max_y: max_y }
      end

      def loop_axis_extent(bends, bounds, axis)
        values = bends.map { |point| point[axis] } +
          bounds.values_at(:"min_#{axis}", :"max_#{axis}")
        values.minmax
      end

      def loop_label_bounds(edge, node, bends)
        x, y = loop_label_anchor(node, bends)
        half_width, height = loop_label_extent(edge)
        { min_x: x - half_width, max_x: x + half_width,
          min_y: y - height, max_y: y }
      end

      def merge_bounds(bounds, min_x, max_x, min_y, max_y)
        return { min_x:, max_x:, min_y:, max_y: } unless bounds

        { min_x: [bounds[:min_x], min_x].min,
          max_x: [bounds[:max_x], max_x].max,
          min_y: [bounds[:min_y], min_y].min,
          max_y: [bounds[:max_y], max_y].max }
      end

      def self_loop_overflow(graph)
        bounds = self_loop_bounds(graph)
        return [0.0, 0.0] unless bounds

        [bounds[:min_x].negative? ? -bounds[:min_x] : 0.0,
         bounds[:min_y].negative? ? -bounds[:min_y] : 0.0]
      end

      def self_loop_reach(graph)
        bounds = self_loop_bounds(graph)
        bounds ? [bounds[:max_x], bounds[:max_y]] : [0.0, 0.0]
      end

      def loop_label_extent(edge)
        label = edge[:labels]&.first
        return [0.0, 0.0] unless label

        width = measure_text(
          label[:text].to_s, font_size: layout_font_size
        )[:width] *
          SUBSTITUTE_FONT_HEADROOM
        height = layout_font_size * TextMeasurement::HEIGHT_RATIO
        [width / 2.0, height]
      end

      def self_loop_node(graph, edge)
        source_id = edge[:sources]&.first
        return unless source_id && source_id == edge[:targets]&.first

        find_endpoint(graph, source_id)
      end

      def find_endpoint(graph, node_id)
        return unless node_id

        find_node(graph[:children], node_id) ||
          find_node(graph[:clusters], node_id)
      end

      def find_node(nodes, node_id)
        (nodes || []).find { |node| node[:id] == node_id }
      end

      def edge_route(edge, graph, source, target)
        if source[:id] == target[:id]
          return self_edge_route(edge, graph, source, target)
        end

        routed_edge(edge, source, target)
      end

      def self_edge_route(edge, graph, source, target)
        bends = edge_bends(edge, source, target, self_loop_side(graph))
        ends = clipped_ends(bends, source, target)
        [ends, bends, ends]
      end

      def routed_edge(edge, source, target)
        elk_bends = edge.dig(:sections, 0, :bendPoints)
        points, label_route = edge_router.route(source, target, elk_bends)
        bends = points.length > 2 ? points[1...-1] : (elk_bends || [])
        if routed_endpoints?(points, source, target)
          return [FlowchartEdgeRouter.ends_of(points), bends, label_route]
        end

        route = clipped_ends(bends, source, target)
        [route, bends, route]
      end

      def routed_endpoints?(points, source, target)
        points.length > 2 || cluster?(source) || cluster?(target)
      end

      def clipped_ends(bends, source, target)
        [*edge_end(bends, source, target, :source),
         *edge_end(bends, source, target, :target)]
      end

      def edge_router
        @edge_router ||= FlowchartEdgeRouter.new
      end

      def edge_end(bends, source, target, which)
        boundary_geometry(bends, source, target, which)
          .values_at(:tip_x, :tip_y).map { |number| number.round(1) }
      end

      def boundary_geometry(bends, source, target, which)
        node, other = which == :target ? [target, source] : [source, target]
        via = which == :target ? bends.last : bends.first
        from_x, from_y = via ? via.values_at(:x, :y) : node_centre(other)
        tip_x, tip_y = node_boundary(node, from_x, from_y)
        { tip_x: tip_x, tip_y: tip_y, from_x: from_x, from_y: from_y }
      end

      def self_loop_side(graph)
        SELF_LOOP_SIDES[graph.dig(:layoutOptions, "elk.direction")] ||
          SELF_LOOP_SIDES["DOWN"]
      end

      def edge_bends(edge, source, target, side)
        bends = edge.dig(:sections, 0, :bendPoints) || []
        return bends unless source[:id] == target[:id] && bends.empty?

        self_loop_bends(source, side)
      end

      def self_loop_bends(node, side)
        out_x, out_y = side
        half_span = self_loop_half_span(node, out_y)
        far_x, far_y = self_loop_outer_point(node, side)
        [{ x: far_x - (out_y.abs * half_span),
           y: far_y - (out_x.abs * half_span) },
         { x: far_x + (out_y.abs * half_span),
           y: far_y + (out_x.abs * half_span) }]
      end

      def self_loop_half_span(node, out_y)
        span_side = out_y.zero? ? node[:height] || 50 : node[:width] || 100
        half_span = (span_side * SELF_LOOP_HALF_SPAN)
          .clamp(SELF_LOOP_HALF_SPAN_LIMITS)
        [half_span, span_side / 2.0].min
      end

      def self_loop_outer_point(node, side)
        cx, cy = node_centre(node)
        out_x, out_y = side
        edge_x, edge_y = node_boundary(node, cx + out_x, cy + out_y)
        depth = self_loop_depth(node)
        [edge_x + (out_x * depth), edge_y + (out_y * depth)]
      end

      def self_loop_depth(node)
        width = node[:width] || 100
        height = node[:height] || 50
        [[width, height].min * SELF_LOOP_DEPTH, SELF_LOOP_MAX_DEPTH].min
      end

      def head_tip_geometry(route, bends, source, target, which)
        node = which == :target ? target : source
        other = which == :target ? :source : :target
        via = which == :target ? bends.last : bends.first
        from_x, from_y = via ? via.values_at(:x, :y) : route_end(route, other)
        tip_x, tip_y = if cluster?(node)
                         route_end(route, which)
                       else
                         node_boundary(node, from_x, from_y)
                       end
        { tip_x: tip_x, tip_y: tip_y, from_x: from_x, from_y: from_y }
      end

      def route_end(route, which)
        which == :target ? route.last(2) : route.first(2)
      end

      def node_centre(node)
        FlowchartEdgeRouter.centre(node).values_at(:x, :y)
      end

      def node_boundary(node, from_x, from_y)
        cx, cy = node_centre(node)
        dx = from_x - cx
        dy = from_y - cy
        return [cx, cy] if dx.zero? && dy.zero?

        scale = boundary_scale(node, dx, dy)
        [cx + (dx * scale), cy + (dy * scale)]
      end

      def boundary_scale(node, delta_x, delta_y)
        half_w = (node[:width] || 100) / 2.0
        half_h = (node[:height] || 50) / 2.0
        shape = NODE_OUTLINES[node.dig(:metadata, :shape)]
        scale_method = BOUNDARY_SCALES.fetch(shape, :box_scale)
        send(scale_method, half_w, half_h, delta_x, delta_y)
      end

      def box_scale(half_w, half_h, delta_x, delta_y)
        [delta_x.zero? ? Float::INFINITY : half_w / delta_x.abs,
         delta_y.zero? ? Float::INFINITY : half_h / delta_y.abs].min
      end

      def rhombus_scale(half_w, half_h, delta_x, delta_y)
        1 / (axis_ratio(delta_x, half_w) + axis_ratio(delta_y, half_h))
      end

      def circle_scale(half_w, half_h, delta_x, delta_y)
        [half_w, half_h].min / Math.hypot(delta_x, delta_y)
      end

      def hexagon_scale(half_w, half_h, delta_x, delta_y)
        slope = 1 / (
          axis_ratio(delta_x, half_w) + axis_ratio(delta_y, 2 * half_h)
        )
        [slope, delta_y.zero? ? Float::INFINITY : half_h / delta_y.abs].min
      end

      def rounded_scale(half_w, half_h, x_diff, y_diff)
        scale = box_scale(half_w, half_h, x_diff, y_diff)
        inner_x = half_w - ROUNDED_CORNER
        inner_y = half_h - ROUNDED_CORNER
        along_x = (x_diff * scale).abs <= inner_x
        along_y = (y_diff * scale).abs <= inner_y
        return scale if along_x || along_y

        cap_intersection(inner_x * (x_diff.negative? ? -1 : 1), ROUNDED_CORNER,
                         x_diff, y_diff, inner_y * (y_diff.negative? ? -1 : 1))
      end

      def stadium_scale(half_w, half_h, x_diff, y_diff)
        return ellipse_scale(half_w, half_h, x_diff, y_diff) if half_w == half_h
        # A tall stadium is a wide one turned on its side.
        return stadium_scale(half_h, half_w, y_diff, x_diff) if half_w < half_h

        flat = y_diff.zero? ? Float::INFINITY : half_h / y_diff.abs
        straight = half_w - half_h
        return flat if (flat * x_diff).abs <= straight

        cap_intersection(straight * (x_diff.negative? ? -1 : 1), half_h,
                         x_diff, y_diff)
      end

      def ellipse_scale(half_w, half_h, delta_x, delta_y)
        x_ratio = axis_ratio(delta_x, half_w)
        y_ratio = axis_ratio(delta_y, half_h)
        1 / Math.sqrt((x_ratio**2) + (y_ratio**2))
      end

      def axis_ratio(delta, half_extent)
        delta.zero? ? 0.0 : delta.abs / half_extent
      end

      def cap_intersection(centre_x, radius, delta_x, delta_y, centre_y = 0)
        a = dot(delta_x, delta_y, delta_x, delta_y)
        b = dot(delta_x, delta_y, centre_x, centre_y)
        c = dot(centre_x, centre_y, centre_x, centre_y) - (radius * radius)
        (b + Math.sqrt([(b * b) - (a * c), 0].max)) / a
      end

      def dot(x_one, y_one, x_two, y_two)
        (x_one * x_two) + (y_one * y_two)
      end

      def edge_label_anchor(source, target, bends, route)
        return loop_label_anchor(source, bends) if source[:id] == target[:id]

        sx, sy, tx, ty = route
        [(sx + tx) / 2.0, ((sy + ty) / 2.0) - EDGE_LABEL_LIFT]
      end

      def loop_label_anchor(node, bends)
        mid_x, mid_y = loop_label_midpoint(bends)
        cx, cy = node_centre(node)
        dx = mid_x - cx
        dy = mid_y - cy
        span = Math.hypot(dx, dy)
        return [mid_x, mid_y] if span.zero?

        [mid_x + ((dx / span) * EDGE_LABEL_LIFT),
         mid_y + ((dy / span) * EDGE_LABEL_LIFT)]
      end

      def loop_label_midpoint(bends)
        [(bends.first[:x] + bends.last[:x]) / 2.0,
         (bends.first[:y] + bends.last[:y]) / 2.0]
      end

      # Subgraphs become compound children holding their members, which is
      # what elkrb reads and what lets the layout size a cluster to fit.
      # A node in no subgraph stays at the top level.
      def transform_children(graph)
        semantic_children = graph.nodes.group_by(&:parent_id)
        boxes = graph.nodes.select { |node| node.role == "group" }
        placed = graph.nodes.select { |node| node.role == "flow_node" }
        assemble(boxes, placed, semantic_children)
      end

      # Model order is kept for emitted clusters. Nested clusters are attached
      # before member nodes, so every cluster lists boxes before nodes. Parent
      # lookup is independent of declaration order, so a later cluster can
      # hold an earlier one.
      #
      def assemble(boxes, placed, semantic_children)
        entries = boxes.map do |box|
          [box, transform_subgraph(box, semantic_children[box.id])]
        end
        clusters_by_id = entries.to_h { |box, cluster| [box.id, cluster] }
        attach_clusters(entries, clusters_by_id)
        loose = unclustered_nodes(placed, semantic_children, clusters_by_id)
        loose + root_clusters(entries, clusters_by_id)
      end

      def root_clusters(entries, clusters_by_id)
        entries.reject { |box, _| clusters_by_id[box.parent_id] }.map(&:last)
      end

      def attach_clusters(entries, clusters_by_id)
        entries.each do |box, cluster|
          clusters_by_id[box.parent_id]&.fetch(:children)&.push(cluster)
        end
      end

      def unclustered_nodes(placed, semantic_children, clusters_by_id)
        placed.each_with_object([]) do |node, top_level|
          transformed = transform_node(node, semantic_children[node.id])
          holder = clusters_by_id[node.parent_id]
          holder ? holder[:children] << transformed : top_level << transformed
        end
      end

      def transform_subgraph(box, semantics)
        { id: semantic_value(semantics, "source_identifier") || box.id,
          width: 0, height: 0, children: [], labels: subgraph_labels(box),
          metadata: { cluster: true, direction: own_direction(semantics) } }
      end

      def subgraph_labels(box)
        title = display_text(box.label)
        label = measure_text(title, font_size: layout_font_size)
        [{ text: title, width: label[:width], height: label[:height] }]
      end

      # The ELK direction a subgraph's own `direction` asks for, nil if it
      # has none.
      def own_direction(semantics)
        written = semantic_value(semantics, "layout_direction")
        direction_to_layout(written) if written
      end

      def transform_node(node, semantics)
        shape = semantic_value(semantics, "shape") || "rect"
        dims = calculate_dimensions(node.label, shape)
        collision = semantic_value(semantics, "subgraph_collision") == "true"
        { id: semantic_value(semantics, "source_identifier") || node.id,
          width: dims[:width], height: dims[:height],
          labels: [transformed_node_label(node, dims)],
          metadata: { shape: shape,
                      classes: semantic_value(semantics, "style_reference"),
                      subgraph_collision: collision,
                      **node_paints(semantics) } }
      end

      def node_paints(semantics)
        %w[fill stroke].to_h do |role|
          [role.to_sym, semantic_value(semantics, role)]
        end
      end

      def transformed_node_label(node, dims)
        { text: Diagram::FlowchartLabelText.lines(node.label).join("\n"),
          width: dims[:label_width], height: dims[:label_height] }
      end

      def compact_collision_nodes(children)
        children.each do |child|
          compact_collision_nodes(child[:children]) if child[:children]
          compact_collision_node(child) if
            child.dig(:metadata, :subgraph_collision)
        end
      end

      def compact_collision_node(child)
        width, height = compact_collision_dimensions(child[:labels].first)
        center_compact_collision(child, width, height)
      end

      def center_compact_collision(child, width, height)
        child[:x] += (child[:width] - width) / 2.0
        child[:y] += (child[:height] - height) / 2.0
        child[:width] = width
        child[:height] = height
      end

      def compact_collision_dimensions(label)
        extra_width, extra_height = COLLISION_NODE_PADDING
        [label[:width] + extra_width, label[:height] + extra_height]
      end

      def transform_edges(graph)
        source_ids = source_identifiers(graph)
        graph.edges.map { |edge| transform_edge(edge, source_ids) }
      end

      def source_identifiers(graph)
        children = graph.nodes.group_by(&:parent_id)
        graph.nodes.to_h do |node|
          source_id = semantic_value(children[node.id], "source_identifier")
          [node.id, source_id || node.id]
        end
      end

      def transform_edge(edge, source_ids)
        source = source_ids.fetch(edge.source_id)
        target = source_ids.fetch(edge.target_id)
        {
          id: "#{source}_to_#{target}", sources: [source], targets: [target],
          labels: edge_labels(edge),
          metadata: {
            arrow_type: edge.role,
            minimum_rank_span: edge.minimum_rank_span,
          }
        }
      end

      def display_text(text)
        Diagram::FlowchartLabelText.display(text)
      end

      def edge_labels(edge)
        return [] if edge.label.nil? || edge.label.empty?

        text = display_text(edge.label)
        line = measure_text(text, font_size: layout_font_size)
        lines = wrapped_lines(text)
        width = lines > 1 ? EDGE_LABEL_WRAP_WIDTH : line[:width]

        [{ text: text, width: width, height: line[:height] * lines }]
      end

      # How many lines mmdc breaks an edge label into: each takes as many
      # words as fit in the wrap width, counting the space after a word,
      # which mmdc keeps on its line.
      def wrapped_lines(text)
        lines = [[]]
        text.split.join(" ").scan(/\S+ ?/).each do |word|
          lines << [] unless fits_edge_label?(lines.last, word)
          lines.last << word
        end
        lines.size
      end

      def fits_edge_label?(line_words, word)
        return true if line_words.empty?

        line = "#{line_words.join}#{word}"
        measure_text(line, font_size: layout_font_size)[:width] <=
          EDGE_LABEL_WRAP_WIDTH
      end

      def calculate_dimensions(label, shape)
        lines = Diagram::FlowchartLabelText.lines(label)
        widest = line_widths(label, lines).max
        line_height = layout_font_size * NODE_LINE_HEIGHT * lines.size

        node_box(widest, line_height, shape)
          .merge(label_width: widest, label_height: line_height)
      end

      def line_widths(label, lines)
        source_lines = label.to_s.split(Diagram::FlowchartLabelText::LINE_BREAK,
                                        -1)
        lines.zip(source_lines).map do |line, source|
          line_width(line) + icon_advance(source)
        end
      end

      def icon_advance(source)
        count = source.to_s.scan(Diagram::FlowchartLabelText::ICON).length
        count * layout_font_size * ICON_ADVANCE_EMS
      end

      def line_width(line)
        measure_text(line, font_size: layout_font_size)[:width]
      end

      def node_box(label_width, label_height, shape)
        if shape == "rhombus"
          return square(label_width + label_height + RHOMBUS_PADDING)
        end
        if CIRCLE_PADDING.key?(shape)
          return square(label_width + CIRCLE_PADDING[shape])
        end

        padded_box(label_width, label_height, shape)
      end

      def square(side)
        { width: side, height: side }
      end

      def padded_box(label_width, label_height, shape)
        extra_width, extra_height = SHAPE_PADDING.fetch(shape, BOX_PADDING)
        extra_width += hexagon_widening(label_height) if shape == "hexagon"
        { width: label_width + extra_width,
          height: label_height + extra_height }
      end

      # mmdc measures a flowchart label in Trebuchet MS, the first face of
      # its stylesheet.
      def measure_text(text, font_size:)
        TextMeasurement.measure_in(:trebuchet, text, font_size: font_size)
      end

      def hexagon_widening(label_height)
        extra = label_height - (layout_font_size * NODE_LINE_HEIGHT)
        HEXAGON_WIDTH_PER_HEIGHT * extra
      end

      def layout_font_size
        self.class.font_size(theme)
      end

      def layout_options(graph)
        settings = graph.nodes.find { |node| node.role == "diagram_settings" }
        children = graph.nodes.select { |node| node.parent_id == settings&.id }
        direction = direction_to_layout(
          semantic_value(children, "layout_direction"),
        )
        build_elk_options(algorithm: ALGORITHM_LAYERED, direction: direction,
                          **flowchart_spacing_options)
      end

      def flowchart_spacing_options
        { ElkOptions::NODE_NODE_SPACING => 50, ElkOptions::LAYER_SPACING => 50,
          ElkOptions::EDGE_NODE_SPACING => 30,
          ElkOptions::EDGE_EDGE_SPACING => 20,
          ElkOptions::NODE_PLACEMENT => "SIMPLE" }
      end

      def diagram_identifier(graph)
        settings = graph.nodes.find { |node| node.role == "diagram_settings" }
        children = graph.nodes.select { |node| node.parent_id == settings&.id }
        semantic_value(children, "diagram_identifier") || graph.id
      end

      def semantic_value(nodes, role)
        (nodes || []).find { |node| node.role == role }&.label
      end

      def direction_to_layout(direction)
        case direction
        when "LR" then DIRECTION_RIGHT
        when "RL" then DIRECTION_LEFT
        when "BT" then DIRECTION_UP
        else DIRECTION_DOWN
        end
      end
    end
  end
end
