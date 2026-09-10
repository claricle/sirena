# frozen_string_literal: true

require_relative "base"
require_relative "architecture_edge_router"

module Sirena
  module Renderer
    # Architecture diagram renderer for converting positioned layouts to SVG
    class ArchitectureRenderer < Base
      # Icon mappings for common service types
      ICON_GLYPHS = {
        "database" => "⬢",
        "server" => "▦",
        "disk" => "◎",
        "cloud" => "☁",
        "internet" => "◈",
        "browser" => "⊞",
      }.freeze

      # Renders a positioned layout to SVG. Routes every edge around
      # whatever else is in the diagram (services, junctions, groups it
      # doesn't belong to) rather than drawing a straight line through it,
      # and sizes the canvas from the routed extent so a detour never
      # draws outside the SVG's own viewBox.
      #
      # @param layout [Hash] positioned layout with service positions
      # @return [Svg::Document] the rendered SVG document
      def render(layout)
        # Routing needs every laid-out box at once (to avoid them), and the
        # canvas needs to be sized from what routing actually draws - both
        # only the renderer has, so both happen before the document exists.
        routed_edges = layout[:edges] ? route_edges(layout) : []
        svg = create_document_from_layout(layout, routed_edges)

        # Render groups first (as backgrounds)
        render_groups(layout, svg) if layout[:groups]

        # Render edges (connections)
        render_routed_edges(routed_edges, svg)

        # Render services on top
        render_services(layout, svg) if layout[:services]

        # Render junctions - routing points with no label or icon
        render_junctions(layout, svg) if layout[:junctions]

        svg
      end

      protected

      # One router for the whole document (same pattern as
      # FlowchartRenderer#edge_router - memoized, holds no per-call state).
      def edge_router
        @edge_router ||= ArchitectureEdgeRouter.new
      end

      # Routes every edge around whatever else is in the diagram. Returns
      # [{ edge:, points: [...] }, ...], one per layout[:edges] entry.
      def route_edges(layout)
        layout[:edges].map do |edge_info|
          edge = edge_info[:edge]
          from = {
            point: { x: edge_info[:from_x], y: edge_info[:from_y] },
            box: find_node(layout, edge.from_id),
            side: edge_info[:from_side],
          }
          to = {
            point: { x: edge_info[:to_x], y: edge_info[:to_y] },
            box: find_node(layout, edge.to_id),
            side: edge_info[:to_side],
          }

          { edge: edge, points: routed_points(edge, from, to, layout) }
        end
      end

      # A raise here is scoped to this one edge. ArchitectureEdgeRouter#route
      # itself never raises by contract (a search failure falls back to the
      # straight line internally - see its shortest_path), but the grid and
      # Dijkstra state it builds have their own way to hit a case that
      # contract doesn't cover; falling back the same way here keeps one
      # degenerate edge from taking the whole render down with it.
      #
      # obstacles_for is computed HERE, inside the rescued scope, rather
      # than passed in as an argument - Ruby evaluates arguments before a
      # method call runs, so a raise from obstacles_for would otherwise
      # happen outside this method's own rescue and escape uncaught.
      def routed_points(edge, from, to, layout)
        edge_router.route(from: from, to: to, obstacles: obstacles_for(edge, layout))
      rescue StandardError
        [from[:point], to[:point]]
      end

      # Every service and junction box other than the edge's own from/to
      # node, plus every group boundary other than one that is an ancestor
      # of (or equal to) either endpoint's own group - an edge is free to
      # roam inside the group it already lives in, only a group it does not
      # belong to is an obstacle.
      def obstacles_for(edge, layout)
        excluded_ids = [edge.from_id, edge.to_id]
        excluded_group_ids = ancestor_group_ids(find_node(layout, edge.from_id)[:group_id], layout) |
          ancestor_group_ids(find_node(layout, edge.to_id)[:group_id], layout)

        nodes = (layout[:services] || {}).values + (layout[:junctions] || {}).values
        node_obstacles = nodes.reject { |info| excluded_ids.include?(node_id(info)) }
        group_obstacles = (layout[:groups] || {}).except(*excluded_group_ids).values

        node_obstacles + group_obstacles
      end

      # Walks Group#parent_id from group_id up to :root/nil, returning every
      # id on the chain (including group_id itself). Empty when group_id is
      # :root (an ungrouped node has no containing group to exclude). Not
      # just the immediate group - nested groups exist in the model
      # (Group#parent_id), and case 003 in the corpus is one such example.
      #
      # `parent_id` chains are grammar-valid but not acyclic - nothing
      # upstream refuses `group a in b` / `group b in a` - so the walk
      # stops the moment it would revisit an id already on the chain,
      # rather than looping forever.
      def ancestor_group_ids(group_id, layout)
        groups = layout[:groups] || {}
        ids = []
        current_id = group_id

        while current_id && current_id != :root && !ids.include?(current_id)
          ids << current_id
          current_id = groups[current_id]&.dig(:group)&.parent_id
        end

        ids
      end

      def find_node(layout, id)
        (layout[:services] || {})[id] || (layout[:junctions] || {})[id]
      end

      def node_id(info)
        info[:service]&.id || info[:junction]&.id
      end

      # layout[:width]/[:height] pre-date routing; the canvas is sized from
      # the larger of that and the real extent of every routed point, so a
      # detour can never draw outside the SVG's own viewBox and get clipped.
      def create_document_from_layout(layout, routed_edges)
        points = routed_edges.flat_map { |routed| routed[:points] }
        width = ([layout[:width] || 800] + points.map { |point| point[:x] }).max
        height = ([layout[:height] || 600] + points.map { |point| point[:y] }).max

        Svg::Document.new(width: width, height: height)
      end

      def render_groups(layout, svg)
        # Render groups in order (parent groups before children)
        layout[:groups].each do |group_id, group_info|
          render_group(group_info, svg)
        end
      end

      def render_group(group_info, svg)
        group = group_info[:group]
        x = group_info[:x]
        y = group_info[:y]
        width = group_info[:width]
        height = group_info[:height]

        # Create group element
        g = Svg::Group.new.tap do |elem|
          elem.id = "group-#{group.id}"
        end

        # Draw group boundary
        boundary = Svg::Rect.new.tap do |rect|
          rect.x = x
          rect.y = y
          rect.width = width
          rect.height = height
          rect.fill = theme_color(:group_background) || "#f0f0f0"
          rect.fill_opacity = "0.3"
          rect.stroke = theme_color(:border_color) || "#999"
          rect.stroke_width = "2"
          rect.stroke_dasharray = "5,5"
          rect.rx = "8"
          rect.ry = "8"
        end

        g.children << boundary

        # Draw group label
        if group.label
          label = Svg::Text.new.tap do |text|
            text.x = x + 10
            text.y = y + 20
            text.content = group.label
            text.font_size = "14"
            text.font_weight = "bold"
            text.fill = theme_color(:text_color) || "#333"
          end

          g.children << label
        end

        # Draw group icon if present
        if group.icon
          icon_text = Svg::Text.new.tap do |text|
            text.x = x + width - 30
            text.y = y + 25
            text.content = icon_glyph(group.icon)
            text.font_size = "20"
            text.fill = theme_color(:text_color) || "#666"
          end

          g.children << icon_text
        end

        svg << g
      end

      def render_services(layout, svg)
        layout[:services].each do |service_id, service_info|
          render_service(service_info, svg)
        end
      end

      def render_service(service_info, svg)
        service = service_info[:service]
        x = service_info[:x]
        y = service_info[:y]
        width = service_info[:width]
        height = service_info[:height]

        # Create service group
        g = Svg::Group.new.tap do |elem|
          elem.id = "service-#{service.id}"
        end

        # Draw service box
        box = Svg::Rect.new.tap do |rect|
          rect.x = x
          rect.y = y
          rect.width = width
          rect.height = height
          apply_theme_to_node(rect)
          rect.rx = "5"
          rect.ry = "5"
        end

        g.children << box

        # Draw service icon
        if service.icon
          icon = Svg::Text.new.tap do |text|
            text.x = x + width / 2
            text.y = y + height / 3
            text.content = icon_glyph(service.icon)
            text.font_size = "24"
            text.text_anchor = "middle"
            text.dominant_baseline = "middle"
            text.fill = theme_color(:text_color) || "#666"
          end

          g.children << icon
        end

        # Draw service label
        if service.label
          label = Svg::Text.new.tap do |text|
            text.x = x + width / 2
            text.y = y + height * 2 / 3
            text.content = service.label
            apply_theme_to_text(text)
            text.text_anchor = "middle"
            text.dominant_baseline = "middle"
            text.font_size = "12"
          end

          g.children << label
        end

        svg << g
      end

      def render_junctions(layout, svg)
        layout[:junctions].each do |junction_id, junction_info|
          render_junction(junction_info, svg)
        end
      end

      def render_junction(junction_info, svg)
        junction = junction_info[:junction]
        x = junction_info[:x]
        y = junction_info[:y]
        width = junction_info[:width]
        height = junction_info[:height]

        g = Svg::Group.new.tap do |elem|
          elem.id = "junction-#{junction.id}"
        end

        dot = Svg::Circle.new.tap do |circle|
          circle.cx = x + (width / 2)
          circle.cy = y + (height / 2)
          circle.r = width / 2
          apply_theme_to_node(circle)
        end

        g.children << dot
        svg << g
      end

      def render_routed_edges(routed_edges, svg)
        routed_edges.each do |routed_edge|
          render_edge(routed_edge, svg)
        end
      end

      def render_edge(routed_edge, svg)
        edge = routed_edge[:edge]
        points = routed_edge[:points]

        # Create edge group
        g = Svg::Group.new.tap do |elem|
          elem.id = "edge-#{edge.from_id}-#{edge.to_id}"
        end

        # Draw connection line
        path = Svg::Path.new.tap do |p|
          p.d = calculate_edge_path(points)
          p.fill = "none"
          apply_theme_to_edge(p)
          p.marker_end = "url(#arrowhead)"
        end

        g.children << path

        # Draw edge label if present, at the midpoint of the FIRST segment
        # actually drawn - the overall midpoint can now sit inside whatever
        # the edge detoured around, matching
        # FlowchartRenderer#create_edge_label's same reasoning.
        if edge.label && !edge.label.empty?
          mid_x = (points[0][:x] + points[1][:x]) / 2
          mid_y = (points[0][:y] + points[1][:y]) / 2

          label = Svg::Text.new.tap do |text|
            text.x = mid_x
            text.y = mid_y - 5
            text.content = edge.label
            text.font_size = "10"
            text.text_anchor = "middle"
            text.fill = theme_color(:text_color) || "#666"
          end

          g.children << label
        end

        svg << g
      end

      def calculate_edge_path(points)
        path_parts = ["M #{points.first[:x]} #{points.first[:y]}"]
        points[1..].each { |point| path_parts << "L #{point[:x]} #{point[:y]}" }
        path_parts.join(" ")
      end

      def icon_glyph(icon_name)
        # Extract base icon name (remove prefixes like "logos:" or "fa:")
        base_name = icon_name.split(":").last

        # Map to glyph or use first letter as fallback
        ICON_GLYPHS[base_name] || base_name[0].upcase
      end

      def calculate_width(layout)
        layout[:width] || 800
      end

      def calculate_height(layout)
        layout[:height] || 600
      end
    end
  end
end