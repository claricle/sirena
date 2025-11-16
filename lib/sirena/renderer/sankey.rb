# frozen_string_literal: true

require_relative "base"
require_relative "../svg/document"
require_relative "../svg/rect"
require_relative "../svg/text"
require_relative "../svg/path"
require_relative "../svg/group"

module Sirena
  module Renderer
    # Sankey renderer for converting Sankey diagrams to SVG.
    #
    # Converts a Sankey diagram model into SVG with nodes as rectangles
    # and flows as curved paths with width proportional to flow values.
    #
    # @example Render a Sankey diagram
    #   renderer = SankeyRenderer.new
    #   svg = renderer.render(sankey_graph)
    class SankeyRenderer < Base
      # Sankey dimensions
      MARGIN_LEFT = 60
      MARGIN_TOP = 100
      MARGIN_RIGHT = 60
      MARGIN_BOTTOM = 60
      TITLE_Y = 40

      # Flow colors (cycle through for visual distinction)
      FLOW_COLORS = [
        "#4472C4", # Blue
        "#ED7D31", # Orange
        "#A5A5A5", # Gray
        "#FFC000", # Yellow
        "#5B9BD5", # Light Blue
        "#70AD47", # Green
        "#C00000", # Red
        "#7030A0"  # Purple
      ].freeze

      # Renders a Sankey diagram to SVG.
      #
      # @param graph [Hash] the sankey graph structure from transform
      # @return [Svg::Document] the rendered SVG document
      def render(graph)
        @graph = graph
        @flow_color_index = 0

        svg = create_document_for_sankey(graph)

        # Render title if present
        render_title(graph, svg) if graph[:title]

        # Render flows first (so they appear behind nodes)
        render_flows(graph, svg)

        # Render nodes on top
        render_nodes(graph, svg)

        svg
      end

      protected

      def create_document_for_sankey(graph)
        width = calculate_width_for_sankey(graph)
        height = calculate_height_for_sankey(graph)

        Svg::Document.new.tap do |doc|
          doc.width = width
          doc.height = height
          doc.view_box = "0 0 #{width} #{height}"
        end
      end

      def calculate_width_for_sankey(graph)
        nodes = graph[:nodes] || []
        return MARGIN_LEFT + MARGIN_RIGHT + 400 if nodes.empty?

        max_x = nodes.map { |n| n[:x] + n[:width] }.max || 400
        MARGIN_LEFT + max_x + MARGIN_RIGHT + 100
      end

      def calculate_height_for_sankey(graph)
        nodes = graph[:nodes] || []
        return MARGIN_TOP + MARGIN_BOTTOM + 300 if nodes.empty?

        max_y = nodes.map { |n| n[:y] + n[:height] }.max || 300
        MARGIN_TOP + max_y + MARGIN_BOTTOM
      end

      def render_title(graph, svg)
        title_text = Svg::Text.new.tap do |t|
          t.x = (svg.width.to_i / 2)
          t.y = TITLE_Y
          t.content = graph[:title]
          t.fill = theme_color(:label_text) || "#000000"
          t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
          t.font_size = (theme_typography(:font_size_large) || 18).to_s
          t.text_anchor = "middle"
          t.font_weight = "bold"
        end
        svg << title_text
      end

      def render_nodes(graph, svg)
        nodes = graph[:nodes] || []

        nodes.each do |node|
          render_node(node, svg)
        end
      end

      def render_node(node, svg)
        x = MARGIN_LEFT + node[:x]
        y = MARGIN_TOP + node[:y]
        width = node[:width]
        height = node[:height]

        # Node rectangle
        node_rect = Svg::Rect.new.tap do |r|
          r.x = x
          r.y = y
          r.width = width
          r.height = height
          r.fill = theme_color(:node_fill) || "#2E86AB"
          r.stroke = theme_color(:node_stroke) || "#1A5276"
          r.stroke_width = "2"
          r.rx = "3"
          r.ry = "3"
        end
        svg << node_rect

        # Node label
        label_x = x + (width / 2)
        label_y = y + (height / 2) + 5

        node_text = Svg::Text.new.tap do |t|
          t.x = label_x
          t.y = label_y
          t.content = node[:label]
          t.fill = theme_color(:node_text) || "#FFFFFF"
          t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
          t.font_size = (theme_typography(:font_size_small) || 11).to_s
          t.text_anchor = "middle"
          t.font_weight = "bold"
        end
        svg << node_text
      end

      def render_flows(graph, svg)
        flows = graph[:flows] || []

        flows.each do |flow|
          render_flow(flow, svg)
        end
      end

      def render_flow(flow, svg)
        return if flow[:self_loop] # Skip self-loops for now

        source_x = MARGIN_LEFT + flow[:source_x]
        source_y = MARGIN_TOP + flow[:source_y]
        target_x = MARGIN_LEFT + flow[:target_x]
        target_y = MARGIN_TOP + flow[:target_y]
        flow_width = flow[:width]

        # Get color for this flow
        color = get_flow_color

        # Create curved path for flow
        path_d = create_flow_path(source_x, source_y, target_x, target_y, flow_width)

        flow_path = Svg::Path.new.tap do |p|
          p.d = path_d
          p.fill = color
          p.opacity = "0.4"
          p.stroke = "none"
        end
        svg << flow_path

        # Optional: render flow value label
        if flow[:value] && flow[:value] > 0
          render_flow_label(flow, source_x, source_y, target_x, target_y, svg)
        end
      end

      def create_flow_path(x1, y1, x2, y2, width)
        # Calculate control points for bezier curve
        dx = x2 - x1
        control_offset = dx * 0.5

        # Calculate perpendicular offset for width
        half_width = width / 2.0

        # Top curve points
        top_y1 = y1 - half_width
        top_y2 = y2 - half_width

        # Bottom curve points
        bottom_y1 = y1 + half_width
        bottom_y2 = y2 + half_width

        # Control points for bezier curves
        cp1_x = x1 + control_offset
        cp2_x = x2 - control_offset

        # Build path: start at top-left, curve to top-right,
        # line down right side, curve back to bottom-left, close
        path_commands = [
          "M #{x1} #{top_y1}",
          "C #{cp1_x} #{top_y1}, #{cp2_x} #{top_y2}, #{x2} #{top_y2}",
          "L #{x2} #{bottom_y2}",
          "C #{cp2_x} #{bottom_y2}, #{cp1_x} #{bottom_y1}, #{x1} #{bottom_y1}",
          "Z"
        ]

        path_commands.join(" ")
      end

      def render_flow_label(flow, x1, y1, x2, y2, svg)
        # Position label at midpoint of flow
        mid_x = (x1 + x2) / 2.0
        mid_y = (y1 + y2) / 2.0

        # Format value (show up to 2 decimal places)
        value_text = format_flow_value(flow[:value])

        label = Svg::Text.new.tap do |t|
          t.x = mid_x
          t.y = mid_y
          t.content = value_text
          t.fill = theme_color(:label_text) || "#333333"
          t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
          t.font_size = (theme_typography(:font_size_small) || 10).to_s
          t.text_anchor = "middle"
        end
        svg << label
      end

      def format_flow_value(value)
        if value == value.to_i
          value.to_i.to_s
        else
          format("%.2f", value).gsub(/\.?0+$/, "")
        end
      end

      def get_flow_color
        color = FLOW_COLORS[@flow_color_index % FLOW_COLORS.length]
        @flow_color_index += 1
        color
      end
    end
  end
end