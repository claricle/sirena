# frozen_string_literal: true

require_relative "base"
require_relative "grid"
require_relative "elk_placement"
require_relative "flowchart/edge_router"
require_relative "../diagram/flowchart"
require_relative "../diagram/flowchart_label_text"
require_relative "../notation/mermaid/ir_adapters/flowchart"

module Sirena
  module Layout
    # Computes final canvas geometry for flowcharts.
    class Flowchart < Base
      # Fallback font size for text measurement, used only when the
      # injected theme has no typography or no font_size_normal set. When
      # a theme is present (the normal case), #layout_font_size measures
      # against its font_size_normal instead -- the same value the
      # renderer draws node and cluster-title text with (D10). Matches
      # Svg::Text::DEFAULT_FONT_SIZE / renderer/flowchart.rb's
      # SVG_DEFAULT_FONT_SIZE, the value the SVG itself falls back to when
      # apply_theme_to_text leaves font_size unset for the same reason --
      # a mismatched fallback would re-open the box/drawn-text gap D10
      # exists to close, just for the no-typography case instead of the
      # has-typography one.
      DEFAULT_FONT_SIZE = 16.0

      CLUSTER_CORNER = FlowchartEdgeRouter::CLUSTER_CORNER
      CLUSTER_TITLE_BASELINE = 20
      EDGE_LABEL_LIFT = 5.0
      SUBSTITUTE_FONT_HEADROOM = 1.2

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
        "rounded" => "rounded", "stadium" => "rounded",
        "circle" => "circle", "double_circle" => "circle",
        "rhombus" => "rhombus", "hexagon" => "hexagon"
      }.freeze

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

      class Label < Lutaml::Model::Serializable
        attribute :text, :string
        attribute :width, :float
        attribute :height, :float
        attribute :x, :float
        attribute :y, :float
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

      # :grid (the default) or :elk. Grid is deleted once :elk becomes the
      # default; the switch exists only until the parity ratchet allows that.
      attr_accessor :placement

      def scene(diagram)
        graph = build_graph(ir_graph(diagram))
        placer.apply(graph)
        scene_from_graph(graph)
      end

      private

      def placer
        placement == :elk ? ElkPlacement : Grid
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
        dx, dy = self_loop_overflow(flat)
        page = shift_page(flat, dx, dy)
        width = calculate_width(page) + 40
        height = calculate_height(page) + 40

        Scene.new(
          id: graph[:id] || "flowchart",
          width: width,
          height: height,
          view_box: "0 0 #{width} #{height}",
          children: typed_children(graph[:children] || [], 0, 0, dx, dy),
          edges: typed_edges(page),
        )
      end

      def flatten(graph)
        clusters = []
        nodes = []
        collect(graph[:children] || [], 0, 0, clusters, nodes)
        graph.merge(children: nodes, clusters: clusters)
      end

      def collect(children, delta_x, delta_y, clusters, nodes)
        children.each do |child|
          placed = child.merge(x: (child[:x] || 0) + delta_x,
                               y: (child[:y] || 0) + delta_y)
          unless child[:children]
            nodes << placed
            next
          end

          clusters << placed.except(:children) if cluster?(child)
          collect(child[:children], placed[:x], placed[:y], clusters, nodes)
        end
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
        (boxes || []).map do |box|
          box.merge(x: (box[:x] || 0) + delta_x,
                    y: (box[:y] || 0) + delta_y)
        end
      end

      def shift_edges(edges, delta_x, delta_y)
        (edges || []).map do |edge|
          sections = edge[:sections]
          next edge unless sections&.any?

          edge.merge(sections: sections.map do |section|
            bends = section[:bendPoints]
            next section unless bends&.any?

            section.merge(bendPoints: bends.map do |point|
              point.merge(x: (point[:x] || 0) + delta_x,
                          y: (point[:y] || 0) + delta_y)
            end)
          end)
        end
      end

      def typed_children(children, parent_x, parent_y, delta_x, delta_y)
        children.map do |child|
          x = (child[:x] || 0) + parent_x + delta_x
          y = (child[:y] || 0) + parent_y + delta_y
          typed_node(child, x, y, delta_x, delta_y)
        end
      end

      def typed_node(node, x_pos, y_pos, delta_x, delta_y)
        width = node[:width] || 100
        height = node[:height] || 50
        is_cluster = cluster?(node)
        shape = node.dig(:metadata, :shape) || "rect"
        kind = is_cluster ? "cluster" : (NODE_OUTLINES[shape] || "rect")

        Node.new(
          id: node[:id], x: x_pos, y: y_pos, width: width, height: height,
          labels: typed_node_labels(
            node, x_pos, y_pos, width, height, is_cluster
          ),
          shape: shape, shape_kind: kind,
          shape_points: polygon_points(kind, x_pos, y_pos, width, height),
          shape_x: is_cluster ? x_pos.to_i : x_pos,
          shape_y: is_cluster ? y_pos.to_i : y_pos,
          shape_width: is_cluster ? width.to_i : width,
          shape_height: is_cluster ? height.to_i : height,
          center_x: x_pos + (width / 2.0), center_y: y_pos + (height / 2.0),
          radius: [width, height].min / 2.0,
          corner_radius: corner_radius(kind, width, height),
          cluster: is_cluster,
          container: node.key?(:children),
          children: typed_children(node[:children] || [], x_pos - delta_x,
                                   y_pos - delta_y, delta_x, delta_y)
        )
      end

      def typed_node_labels(node, x_pos, y_pos, width, height, cluster)
        (node[:labels] || []).first(1).map do |label|
          Label.new(
            text: label[:text], width: label[:width], height: label[:height],
            x: cluster ? x_pos + (width.to_i / 2) : x_pos + (width / 2.0),
            y: cluster ? y_pos + CLUSTER_TITLE_BASELINE : y_pos + (height / 2.0)
          )
        end
      end

      def polygon_points(kind, x_pos, y_pos, width, height)
        case kind
        when "rhombus"
          cx = x_pos + (width / 2.0)
          cy = y_pos + (height / 2.0)
          [[cx, y_pos], [x_pos + width, cy], [cx, y_pos + height], [x_pos, cy]]
            .map { |px, py| "#{px},#{py}" }.join(" ")
        when "hexagon"
          cy = y_pos + (height / 2.0)
          quarter = width / 4.0
          [[x_pos + quarter, y_pos], [x_pos + width - quarter, y_pos],
           [x_pos + width, cy], [x_pos + width - quarter, y_pos + height],
           [x_pos + quarter, y_pos + height], [x_pos, cy]]
            .map { |px, py| "#{px},#{py}" }.join(" ")
        end
      end

      def corner_radius(kind, _width, height)
        return CLUSTER_CORNER if kind == "cluster"
        return height / 2.0 if kind == "rounded"

        0.0
      end

      def typed_edges(graph)
        (graph[:edges] || []).filter_map do |edge|
          source = find_endpoint(graph, edge[:sources]&.first)
          target = find_endpoint(graph, edge[:targets]&.first)
          next unless source && target

          route, bends, label_route = edge_route(edge, graph, source, target)
          type = edge.dig(:metadata, :arrow_type).to_s
          Edge.new(
            id: edge[:id], source: source[:id], target: target[:id],
            sections: [typed_section(route, bends)],
            labels: typed_edge_labels(edge, source, target, bends, label_route),
            arrow_type: type,
            path: edge_path(route, bends),
            heads: typed_heads(route, bends, source, target, type)
          )
        end
      end

      def typed_section(route, bends)
        Section.new(
          start_point: Point.new(x: route[0], y: route[1]),
          end_point: Point.new(x: route[2], y: route[3]),
          bend_points: bends.map { |point| Point.new(x: point[:x], y: point[:y]) },
        )
      end

      def typed_edge_labels(edge, source, target, bends, route)
        (edge[:labels] || []).first(1).map do |label|
          x, y = edge_label_anchor(source, target, bends, route)
          Label.new(text: label[:text], width: label[:width], height: label[:height],
                    x: x, y: y)
        end
      end

      def edge_path(route, bends)
        sx, sy, tx, ty = route
        return "M #{sx} #{sy} L #{tx} #{ty}" if bends.empty?

        (["M #{sx} #{sy}"] + bends.map do |point|
          "L #{point[:x].round(1)} #{point[:y].round(1)}"
        end + ["L #{tx} #{ty}"]).join(" ")
      end

      def typed_heads(route, bends, source, target, type)
        shape = EDGE_HEADS[type.sub(/\A(?:thick|dotted)_/, "").delete_suffix("_both")]
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
        tip_x, tip_y, from_x, from_y =
          geometry.values_at(:tip_x, :tip_y, :from_x, :from_y)
        along_x, along_y = unit_towards(tip_x, tip_y, from_x, from_y)
        back_x = tip_x + (along_x * ARROW_LENGTH)
        back_y = tip_y + (along_y * ARROW_LENGTH)
        points = [
          [tip_x, tip_y],
          [back_x - (along_y * ARROW_HALF_WIDTH),
           back_y + (along_x * ARROW_HALF_WIDTH)],
          [back_x + (along_y * ARROW_HALF_WIDTH),
           back_y - (along_x * ARROW_HALF_WIDTH)],
        ].map { |x, y| "#{x.round(1)},#{y.round(1)}" }.join(" ")
        Head.new(shape: "arrow", points: points)
      end

      def circle_head(geometry)
        x, y = backed_off(geometry, CIRCLE_HEAD_REACH)
        Head.new(shape: "circle", x: x.round(1), y: y.round(1),
                 radius: CIRCLE_HEAD_RADIUS)
      end

      def cross_head(geometry)
        tip_x, tip_y = backed_off(geometry, CROSS_HEAD_REACH)
        from_x, from_y = geometry.values_at(:from_x, :from_y)
        along_x, along_y = unit_towards(tip_x, tip_y, from_x, from_y)
        along_x = 1.0 if along_x.zero? && along_y.zero?
        arm_x = (along_x - along_y) * CROSS_HEAD_HALF
        arm_y = (along_y + along_x) * CROSS_HEAD_HALF
        lines = [[arm_x, arm_y], [arm_y, -arm_x]].map do |line_x, line_y|
          Line.new(x1: (tip_x - line_x).round(1), y1: (tip_y - line_y).round(1),
                   x2: (tip_x + line_x).round(1), y2: (tip_y + line_y).round(1))
        end
        Head.new(shape: "cross", lines: lines)
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
        return 0 if boxes.empty?

        max_x = boxes.map { |node| (node[:x] || 0) + (node[:width] || 100) }.max
        [max_x, self_loop_reach(graph)[0]].max + 40
      end

      def calculate_height(graph)
        boxes = drawn(graph)
        return 0 if boxes.empty?

        max_y = boxes.map { |node| (node[:y] || 0) + (node[:height] || 50) }.max
        [max_y, self_loop_reach(graph)[1]].max + 40
      end

      def drawn(graph)
        (graph[:children] || []) + (graph[:clusters] || [])
      end

      def self_loop_bounds(graph)
        side = self_loop_side(graph)
        (graph[:edges] || []).reduce(nil) do |bounds, edge|
          node = self_loop_node(graph, edge)
          next bounds unless node

          bends = edge_bends(edge, node, node, side)
          next bounds if bends.empty?

          label_x, label_y = loop_label_anchor(node, bends)
          half_width, height = loop_label_extent(edge)
          xs = bends.map { |point| point[:x] } +
            [label_x - half_width, label_x + half_width]
          ys = bends.map { |point| point[:y] } + [label_y - height, label_y]
          merge_bounds(bounds, xs.min, xs.max, ys.min, ys.max)
        end
      end

      def merge_bounds(bounds, min_x, max_x, min_y, max_y)
        return { min_x: min_x, max_x: max_x, min_y: min_y, max_y: max_y } unless bounds

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

        width = measure_text(label[:text].to_s, font_size: edge_label_font_size)[:width] *
          SUBSTITUTE_FONT_HEADROOM
        height = edge_label_font_size * TextMeasurement::HEIGHT_RATIO
        [width / 2.0, height]
      end

      def self_loop_node(graph, edge)
        source_id = edge[:sources]&.first
        return unless source_id && source_id == edge[:targets]&.first

        find_endpoint(graph, source_id)
      end

      def find_endpoint(graph, node_id)
        return unless node_id

        (graph[:children] || []).find { |node| node[:id] == node_id } ||
          (graph[:clusters] || []).find { |cluster| cluster[:id] == node_id }
      end

      def edge_route(edge, graph, source, target)
        if source[:id] == target[:id]
          bends = edge_bends(edge, source, target, self_loop_side(graph))
          ends = clipped_ends(bends, source, target)
          return [ends, bends, ends]
        end

        elk_bends = edge.dig(:sections, 0, :bendPoints)
        points, label_route = edge_router.route(source, target, elk_bends)
        bends = points.length > 2 ? points[1...-1] : (elk_bends || [])
        if points.length > 2 || cluster?(source) || cluster?(target)
          return [FlowchartEdgeRouter.ends_of(points), bends, label_route]
        end

        route = clipped_ends(bends, source, target)
        [route, bends, route]
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
        approach = which == :target ? bends.last : bends.first
        from_x, from_y = approach ? approach.values_at(:x, :y) : node_centre(other)
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
        cx, cy = node_centre(node)
        width = node[:width] || 100
        height = node[:height] || 50
        out_x, out_y = side
        span_side = out_y.zero? ? height : width
        half_span =
          (span_side * SELF_LOOP_HALF_SPAN).clamp(SELF_LOOP_HALF_SPAN_LIMITS)
        half_span = [half_span, span_side / 2.0].min
        depth = [[width, height].min * SELF_LOOP_DEPTH, SELF_LOOP_MAX_DEPTH].min
        edge_x, edge_y = node_boundary(node, cx + out_x, cy + out_y)
        far_x = edge_x + (out_x * depth)
        far_y = edge_y + (out_y * depth)
        [{ x: far_x - (out_y.abs * half_span),
           y: far_y - (out_x.abs * half_span) },
         { x: far_x + (out_y.abs * half_span),
           y: far_y + (out_x.abs * half_span) }]
      end

      def head_tip_geometry(route, bends, source, target, which)
        node = which == :target ? target : source
        other = which == :target ? :source : :target
        approach = which == :target ? bends.last : bends.first
        from_x, from_y = approach ? approach.values_at(:x, :y) : route_end(route, other)
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
        case NODE_OUTLINES[node.dig(:metadata, :shape)]
        when "rhombus" then rhombus_scale(half_w, half_h, delta_x, delta_y)
        when "circle" then circle_scale(half_w, half_h, delta_x, delta_y)
        when "hexagon" then hexagon_scale(half_w, half_h, delta_x, delta_y)
        when "rounded" then stadium_scale(half_w, half_h, delta_x, delta_y)
        else box_scale(half_w, half_h, delta_x, delta_y)
        end
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

      def stadium_scale(half_w, half_h, x_diff, y_diff)
        return ellipse_scale(half_w, half_h, x_diff, y_diff) if half_w <= half_h

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

      def cap_intersection(centre_x, radius, delta_x, delta_y)
        a = (delta_x * delta_x) + (delta_y * delta_y)
        b = delta_x * centre_x
        c = (centre_x * centre_x) - (radius * radius)
        (b + Math.sqrt([(b * b) - (a * c), 0].max)) / a
      end

      def edge_label_anchor(source, target, bends, route)
        return loop_label_anchor(source, bends) if source[:id] == target[:id]

        sx, sy, tx, ty = route
        [(sx + tx) / 2.0, ((sy + ty) / 2.0) - EDGE_LABEL_LIFT]
      end

      def loop_label_anchor(node, bends)
        mid_x = (bends.first[:x] + bends.last[:x]) / 2.0
        mid_y = (bends.first[:y] + bends.last[:y]) / 2.0
        cx, cy = node_centre(node)
        span = Math.hypot(mid_x - cx, mid_y - cy)
        return [mid_x, mid_y] if span.zero?

        [mid_x + (((mid_x - cx) / span) * EDGE_LABEL_LIFT),
         mid_y + (((mid_y - cy) / span) * EDGE_LABEL_LIFT)]
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

        # Clusters first, so every cluster lists its boxes before its
        # nodes.
        entries.each do |box, cluster|
          clusters_by_id[box.parent_id]&.fetch(:children)&.push(cluster)
        end

        loose = placed.each_with_object([]) do |node, top_level|
          transformed = transform_node(node, semantic_children[node.id])
          holder = clusters_by_id[node.parent_id]
          holder ? holder[:children] << transformed : top_level << transformed
        end

        loose + entries.reject { |box, _| clusters_by_id[box.parent_id] }
          .map(&:last)
      end

      def transform_subgraph(box, semantics)
        title = display_text(box.label)
        label = measure_text(title, font_size: layout_font_size)

        {
          id: semantic_value(semantics, "source_identifier") || box.id,
          width: 0,
          height: 0,
          children: [],
          labels: [
            { text: title, width: label[:width], height: label[:height] },
          ],
          metadata: { cluster: true },
        }
      end

      def transform_node(node, semantics)
        shape = semantic_value(semantics, "shape") || "rect"
        dims = calculate_dimensions(node.label, shape)

        {
          id: semantic_value(semantics, "source_identifier") || node.id,
          width: dims[:width],
          height: dims[:height],
          labels: [
            {
              text: display_text(node.label),
              width: dims[:label_width],
              height: dims[:label_height],
            },
          ],
          metadata: {
            shape: shape,
            classes: semantic_value(semantics, "style_reference"),
          },
        }
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
          labels: edge_labels(edge), metadata: { arrow_type: edge.role }
        }
      end

      def display_text(text)
        Diagram::FlowchartLabelText.display(text)
      end

      def edge_labels(edge)
        return [] if edge.label.nil? || edge.label.empty?

        text = display_text(edge.label)
        label_dims = measure_text(text, font_size: edge_label_font_size)

        [
          {
            text: text,
            width: label_dims[:width],
            height: label_dims[:height],
          },
        ]
      end

      def calculate_dimensions(label, shape)
        label_dims = measure_text(
          display_text(label),
          font_size: layout_font_size,
        )

        node_dims = calculate_node_dimensions(
          label_dims[:width],
          label_dims[:height],
          shape_to_type(shape),
        )

        {
          width: node_dims[:width],
          height: node_dims[:height],
          label_width: label_dims[:width],
          label_height: label_dims[:height],
        }
      end

      # The size node and cluster-title measure_text calls size against:
      # the injected theme's font_size_normal, the same value
      # apply_theme_to_text sets on node and cluster-title text at render
      # time (renderer/base.rb, renderer/flowchart.rb#create_node_label,
      # #cluster_title). Falls back to DEFAULT_FONT_SIZE only when the
      # theme has no typography or no font_size_normal. NOT used for edge
      # labels -- see #edge_label_font_size.
      def layout_font_size
        valid_font_size(theme&.typography&.font_size_normal) || DEFAULT_FONT_SIZE
      end

      # The size edge-label measure_text calls size against, mirroring the
      # renderer's own preference order for the text it actually draws
      # (renderer/flowchart.rb#edge_label_font_size: font_size_small first,
      # since edge labels draw at the small size when the theme sets one).
      # Keeping the two in step means the layout reserves room for the font
      # the renderer draws with, not a different one.
      def edge_label_font_size
        valid_font_size(theme&.typography&.font_size_small) ||
          valid_font_size(theme&.typography&.font_size_normal) || DEFAULT_FONT_SIZE
      end

      # A theme-supplied font size flows unchecked into TextMeasurement's
      # box-size arithmetic (summed glyph advances times it). A non-finite
      # value (NaN, Infinity) raises deep inside Float comparison, and a
      # non-positive one produces an invalid negative SVG width -- both
      # unvalidated anywhere else on this path (Typography's font_size_*
      # attributes carry no range check). Falls through to DEFAULT_FONT_SIZE
      # the same way a missing value does.
      def valid_font_size(value)
        value if value.is_a?(Numeric) && value.finite? && value.positive?
      end

      def shape_to_type(shape)
        case shape
        when "rect", "subroutine"
          :rect
        when "circle", "double_circle"
          :circle
        when "rhombus", "hexagon"
          :diamond
        else
          :rect
        end
      end

      def layout_options(graph)
        settings = graph.nodes.find { |node| node.role == "diagram_settings" }
        children = graph.nodes.select { |node| node.parent_id == settings&.id }
        direction = direction_to_layout(
          semantic_value(children, "layout_direction"),
        )

        # Flowcharts use layered algorithm for hierarchical flow
        # This ensures nodes are placed in distinct layers and edges flow
        # in the specified direction with minimal crossings
        build_elk_options(
          algorithm: ALGORITHM_LAYERED,
          direction: direction,
          # Additional flowchart-specific options
          ElkOptions::NODE_NODE_SPACING => 50,
          ElkOptions::LAYER_SPACING => 50,
          ElkOptions::EDGE_NODE_SPACING => 30,
          ElkOptions::EDGE_EDGE_SPACING => 20,
          # SIMPLE node placement for predictable, straightforward layouts
          # This is ideal for flowcharts where clarity is paramount
          ElkOptions::NODE_PLACEMENT => "SIMPLE",
        )
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
        when "TD", "TB"
          DIRECTION_DOWN
        when "LR"
          DIRECTION_RIGHT
        when "RL"
          DIRECTION_LEFT
        when "BT"
          DIRECTION_UP
        else
          DIRECTION_DOWN # Default direction
        end
      end
    end
  end
end
