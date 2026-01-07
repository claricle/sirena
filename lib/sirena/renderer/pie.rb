# frozen_string_literal: true

require_relative 'base'
require_relative '../svg/document'
require_relative '../svg/circle'
require_relative '../svg/path'
require_relative '../svg/text'
require_relative '../svg/group'

module Sirena
  module Renderer
    # Pie chart renderer for converting pie diagrams to SVG.
    #
    # Converts a Pie diagram model into SVG with calculated slice angles,
    # colors from theme, labels, and optional data values.
    #
    # @example Render a pie chart
    #   renderer = PieRenderer.new
    #   svg = renderer.render(pie_diagram)
    class PieRenderer < Base
      # Pie chart dimensions
      PIE_RADIUS = 150
      PIE_CENTER_X = 250
      PIE_CENTER_Y = 200
      LABEL_OFFSET = 180 # Distance from center for labels
      TITLE_Y = 40

      # Default color palette for slices
      DEFAULT_COLORS = [
        '#4472C4', '#ED7D31', '#A5A5A5', '#FFC000',
        '#5B9BD5', '#70AD47', '#264478', '#9E480E',
        '#636363', '#997300', '#255E91', '#43682B'
      ].freeze

      # Renders a pie chart diagram to SVG.
      #
      # @param graph [Hash] the pie chart graph structure from transform
      # @return [Svg::Document] the rendered SVG document
      def render(graph)
        svg = create_document_for_pie(graph)

        # Render title if present
        render_title(graph, svg) if graph[:title]

        # Render pie slices
        render_slices(graph, svg)

        # Render labels
        render_labels(graph, svg)

        svg
      end

      protected

      def create_document_for_pie(graph)
        width = calculate_width_for_pie(graph)
        height = calculate_height_for_pie(graph)

        Svg::Document.new.tap do |doc|
          doc.width = width
          doc.height = height
          doc.view_box = "0 0 #{width} #{height}"
        end
      end

      def calculate_width_for_pie(_graph)
        500 # Fixed width for pie chart
      end

      def calculate_height_for_pie(graph)
        base_height = 400
        base_height += 60 if graph[:title] # Add space for title
        base_height
      end

      def render_title(graph, svg)
        title_text = Svg::Text.new.tap do |t|
          t.x = PIE_CENTER_X
          t.y = TITLE_Y
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

      def render_slices(graph, svg)
        slices = graph[:slices] || []
        return if slices.empty?

        start_angle = -90.0 # Start at top (12 o'clock)

        slices.each_with_index do |slice, index|
          angle = slice[:angle]
          end_angle = start_angle + angle

          # Get color for this slice
          color = get_slice_color(index)

          # Render the slice
          render_slice(
            start_angle,
            end_angle,
            color,
            svg,
            index
          )

          start_angle = end_angle
        end
      end

      def render_slice(start_angle, end_angle, color, svg, index)
        # Create SVG path for pie slice
        path_data = create_pie_slice_path(start_angle, end_angle)

        path = Svg::Path.new.tap do |p|
          p.d = path_data
          p.fill = color
          p.stroke = theme_color(:node_stroke) || '#ffffff'
          p.stroke_width = '2'
          p.id = "slice-#{index}"
        end

        svg << path
      end

      def create_pie_slice_path(start_angle, end_angle)
        # Convert angles to radians
        start_rad = degrees_to_radians(start_angle)
        end_rad = degrees_to_radians(end_angle)

        # Calculate start and end points on the circle
        start_x = PIE_CENTER_X + PIE_RADIUS * Math.cos(start_rad)
        start_y = PIE_CENTER_Y + PIE_RADIUS * Math.sin(start_rad)
        end_x = PIE_CENTER_X + PIE_RADIUS * Math.cos(end_rad)
        end_y = PIE_CENTER_Y + PIE_RADIUS * Math.sin(end_rad)

        # Determine if we need a large arc
        large_arc = (end_angle - start_angle) > 180 ? 1 : 0

        # Create path: Move to center, line to start, arc to end, close path
        [
          "M #{PIE_CENTER_X} #{PIE_CENTER_Y}",
          "L #{start_x} #{start_y}",
          "A #{PIE_RADIUS} #{PIE_RADIUS} 0 #{large_arc} 1 #{end_x} #{end_y}",
          'Z'
        ].join(' ')
      end

      def render_labels(graph, svg)
        slices = graph[:slices] || []
        return if slices.empty?

        start_angle = -90.0 # Start at top

        slices.each do |slice|
          angle = slice[:angle]
          mid_angle = start_angle + (angle / 2.0)

          # Calculate label position
          label_x, label_y = calculate_label_position(mid_angle)

          # Render label
          render_label(
            slice[:label],
            slice[:percentage],
            label_x,
            label_y,
            svg,
            graph[:show_data]
          )

          start_angle += angle
        end
      end

      def calculate_label_position(angle)
        rad = degrees_to_radians(angle)
        x = PIE_CENTER_X + LABEL_OFFSET * Math.cos(rad)
        y = PIE_CENTER_Y + LABEL_OFFSET * Math.sin(rad)
        [x, y]
      end

      def render_label(label, percentage, x, y, svg, show_data)
        # Format label text
        label_text = label
        label_text += ": #{percentage.round(1)}%" if show_data

        text = Svg::Text.new.tap do |t|
          t.x = x
          t.y = y
          t.content = label_text
          t.fill = theme_color(:label_text) || '#000000'
          t.font_family = theme_typography(:font_family) ||
                          'Arial, sans-serif'
          t.font_size = (theme_typography(:font_size_small) || 12).to_s
          t.text_anchor = 'middle'
          t.dominant_baseline = 'middle'
        end

        svg << text
      end

      def get_slice_color(index)
        # Use theme colors if available, otherwise use default palette
        if theme && theme.colors
          # Try to get pie-specific colors from theme
          color_key = "pie_slice_#{index}".to_sym
          theme_color(color_key) || DEFAULT_COLORS[index % DEFAULT_COLORS.length]
        else
          DEFAULT_COLORS[index % DEFAULT_COLORS.length]
        end
      end

      def degrees_to_radians(degrees)
        degrees * Math::PI / 180.0
      end

      # Override base class methods for pie chart specific calculations
      def calculate_width(_graph)
        500
      end

      def calculate_height(_graph)
        400
      end
    end
  end
end