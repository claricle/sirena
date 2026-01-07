# frozen_string_literal: true

require_relative 'base'
require_relative '../svg/document'
require_relative '../svg/rect'
require_relative '../svg/line'
require_relative '../svg/circle'
require_relative '../svg/text'
require_relative '../svg/group'

module Sirena
  module Renderer
    # Quadrant chart renderer for converting quadrant diagrams to SVG.
    #
    # Converts a QuadrantChart diagram model into SVG with a 2x2 grid,
    # axis labels, quadrant labels, and data points.
    #
    # @example Render a quadrant chart
    #   renderer = QuadrantRenderer.new
    #   svg = renderer.render(quadrant_graph)
    class QuadrantRenderer < Base
      # Quadrant colors (can be overridden by theme)
      QUADRANT_COLORS = {
        1 => '#e3f2fd', # Light blue
        2 => '#fff3e0', # Light orange
        3 => '#f3e5f5', # Light purple
        4 => '#e8f5e9'  # Light green
      }.freeze

      # Renders a quadrant chart diagram to SVG.
      #
      # @param graph [Hash] the quadrant chart graph structure from transform
      # @return [Svg::Document] the rendered SVG document
      def render(graph)
        svg = create_document(graph)

        # Render title if present
        render_title(graph, svg) if graph[:title]

        # Render quadrant grid
        render_quadrants(graph, svg)

        # Render axes
        render_axes(graph, svg)

        # Render axis labels
        render_axis_labels(graph, svg)

        # Render quadrant labels
        render_quadrant_labels(graph, svg)

        # Render data points
        render_points(graph, svg)

        svg
      end

      protected

      def create_document(graph)
        dims = graph[:dimensions]

        Svg::Document.new.tap do |doc|
          doc.width = dims[:width]
          doc.height = dims[:height]
          doc.view_box = "0 0 #{dims[:width]} #{dims[:height]}"
        end
      end

      def render_title(graph, svg)
        dims = graph[:dimensions]

        title_text = Svg::Text.new.tap do |t|
          t.x = dims[:width] / 2
          t.y = 30
          t.content = graph[:title]
          t.fill = theme_color(:label_text) || '#000000'
          t.font_family = theme_typography(:font_family) ||
                          'Arial, sans-serif'
          t.font_size = (theme_typography(:font_size_large) || 18).to_s
          t.text_anchor = 'middle'
          t.font_weight = 'bold'
        end
        svg << title_text
      end

      def render_quadrants(graph, svg)
        quadrants = graph[:quadrants]

        # Render each quadrant background
        quadrants.each do |_key, quadrant|
          bounds = quadrant[:bounds]
          color = get_quadrant_color(quadrant[:number])

          rect = Svg::Rect.new.tap do |r|
            r.x = bounds[:x]
            r.y = bounds[:y]
            r.width = bounds[:width]
            r.height = bounds[:height]
            r.fill = color
            r.stroke = theme_color(:grid_line) || '#cccccc'
            r.stroke_width = '1'
            r.opacity = '0.3'
          end
          svg << rect
        end
      end

      def render_axes(graph, svg)
        dims = graph[:dimensions]

        # Vertical axis (center)
        center_x = dims[:chart_x] + (dims[:chart_width] / 2)
        vertical_line = Svg::Line.new.tap do |line|
          line.x1 = center_x
          line.y1 = dims[:chart_y]
          line.x2 = center_x
          line.y2 = dims[:chart_y] + dims[:chart_height]
          line.stroke = theme_color(:grid_line) || '#666666'
          line.stroke_width = '2'
        end
        svg << vertical_line

        # Horizontal axis (center)
        center_y = dims[:chart_y] + (dims[:chart_height] / 2)
        horizontal_line = Svg::Line.new.tap do |line|
          line.x1 = dims[:chart_x]
          line.y1 = center_y
          line.x2 = dims[:chart_x] + dims[:chart_width]
          line.y2 = center_y
          line.stroke = theme_color(:grid_line) || '#666666'
          line.stroke_width = '2'
        end
        svg << horizontal_line
      end

      def render_axis_labels(graph, svg)
        dims = graph[:dimensions]
        axes = graph[:axes]

        # X-axis left label
        render_axis_label(
          axes[:x_left],
          dims[:chart_x] - 10,
          dims[:chart_y] + dims[:chart_height] + 30,
          'end',
          svg
        )

        # X-axis right label
        render_axis_label(
          axes[:x_right],
          dims[:chart_x] + dims[:chart_width] + 10,
          dims[:chart_y] + dims[:chart_height] + 30,
          'start',
          svg
        )

        # Y-axis bottom label
        render_axis_label(
          axes[:y_bottom],
          dims[:chart_x] - 30,
          dims[:chart_y] + dims[:chart_height] + 10,
          'middle',
          svg
        )

        # Y-axis top label
        render_axis_label(
          axes[:y_top],
          dims[:chart_x] - 30,
          dims[:chart_y] - 10,
          'middle',
          svg
        )
      end

      def render_axis_label(text, x, y, anchor, svg)
        return unless text

        label = Svg::Text.new.tap do |t|
          t.x = x
          t.y = y
          t.content = text
          t.fill = theme_color(:label_text) || '#666666'
          t.font_family = theme_typography(:font_family) ||
                          'Arial, sans-serif'
          t.font_size = (theme_typography(:font_size_small) || 12).to_s
          t.text_anchor = anchor
        end
        svg << label
      end

      def render_quadrant_labels(graph, svg)
        quadrants = graph[:quadrants]

        quadrants.each do |_key, quadrant|
          next unless quadrant[:label]

          bounds = quadrant[:bounds]

          # Calculate center position for label
          label_x = bounds[:x] + (bounds[:width] / 2)
          label_y = bounds[:y] + 20

          label = Svg::Text.new.tap do |t|
            t.x = label_x
            t.y = label_y
            t.content = quadrant[:label]
            t.fill = theme_color(:label_text) || '#333333'
            t.font_family = theme_typography(:font_family) ||
                            'Arial, sans-serif'
            t.font_size = (theme_typography(:font_size_normal) || 14).to_s
            t.text_anchor = 'middle'
            t.font_weight = 'bold'
            t.opacity = '0.7'
          end
          svg << label
        end
      end

      def render_points(graph, svg)
        points = graph[:points] || []

        points.each do |point|
          render_point(point, svg)
          render_point_label(point, svg)
        end
      end

      def render_point(point, svg)
        radius = point[:radius] || 6
        color = point[:color] || get_point_color(point[:quadrant])
        stroke_color = point[:stroke_color] ||
                       theme_color(:node_stroke) ||
                       '#ffffff'
        stroke_width = point[:stroke_width] || 2

        circle = Svg::Circle.new.tap do |c|
          c.cx = point[:svg_x]
          c.cy = point[:svg_y]
          c.r = radius
          c.fill = color
          c.stroke = stroke_color
          c.stroke_width = stroke_width.to_s
          c.id = point[:id]
        end
        svg << circle
      end

      def render_point_label(point, svg)
        # Position label slightly above and to the right of point
        label_x = point[:svg_x] + 10
        label_y = point[:svg_y] - 10

        label = Svg::Text.new.tap do |t|
          t.x = label_x
          t.y = label_y
          t.content = point[:label]
          t.fill = theme_color(:label_text) || '#000000'
          t.font_family = theme_typography(:font_family) ||
                          'Arial, sans-serif'
          t.font_size = (theme_typography(:font_size_small) || 11).to_s
          t.text_anchor = 'start'
        end
        svg << label
      end

      def get_quadrant_color(quadrant_number)
        # Try to get from theme first
        color_key = "quadrant_#{quadrant_number}".to_sym
        theme_color(color_key) || QUADRANT_COLORS[quadrant_number]
      end

      def get_point_color(quadrant_number)
        # Use darker version of quadrant color for points
        case quadrant_number
        when 1
          theme_color(:primary) || '#2196f3'
        when 2
          theme_color(:secondary) || '#ff9800'
        when 3
          theme_color(:accent) || '#9c27b0'
        when 4
          theme_color(:success) || '#4caf50'
        else
          theme_color(:primary) || '#2196f3'
        end
      end
    end
  end
end