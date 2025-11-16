# frozen_string_literal: true

require_relative "../svg/document"
require_relative "../svg/circle"
require_relative "../svg/line"
require_relative "../svg/rect"
require_relative "../svg/polyline"
require_relative "../svg/text"
require_relative "../svg/group"

module Sirena
  module Renderer
    # Renders an XY Chart layout to SVG.
    #
    # The renderer converts the positioned layout structure from
    # Transform::XYChart into an SVG visualization showing:
    # - X and Y axes with labels
    # - Grid lines
    # - Data points for line charts
    # - Bars for bar charts
    # - Legend
    #
    # @example Render an XY chart
    #   renderer = Renderer::XYChart.new(theme: my_theme)
    #   svg = renderer.render(layout)
    class XYChart < Base
      # Default colors for datasets (cycling)
      DEFAULT_COLORS = %w[
        #2563eb #7c3aed #db2777 #ea580c #ca8a04
        #16a34a #0891b2 #4f46e5 #c026d3 #dc2626
      ].freeze

      # Number of grid lines on Y-axis
      GRID_LINES = 5

      # Bar width ratio (fraction of available space)
      BAR_WIDTH_RATIO = 0.6

      # Renders the layout structure to SVG.
      #
      # @param layout [Hash] layout data from Transform::XYChart
      # @return [Svg::Document] rendered SVG document
      def render(layout)
        svg = create_document_from_layout(layout)

        # Store layout for rendering
        @layout = layout

        # Render in order: grid, axes, data, labels, legend
        render_title(layout, svg) if layout[:title]
        render_grid(layout, svg)
        render_axes(layout, svg)
        render_datasets(layout, svg)
        render_axis_labels(layout, svg)
        render_legend(layout, svg)

        svg
      end

      protected

      # Creates an SVG document with dimensions from layout.
      #
      # @param layout [Hash] layout data
      # @return [Svg::Document] new SVG document
      def create_document_from_layout(layout)
        Svg::Document.new.tap do |doc|
          doc.width = layout[:width]
          doc.height = layout[:height]
          doc.view_box = "0 0 #{doc.width} #{doc.height}"
        end
      end

      # Renders the chart title.
      #
      # @param layout [Hash] layout data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_title(layout, svg)
        text = Svg::Text.new.tap do |t|
          t.x = layout[:width] / 2
          t.y = 30
          t.text_anchor = "middle"
          t.fill = theme_color(:label_text) || "#000000"
          t.font_size = (theme_typography(:font_size_large) || 16).to_s
          t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
          t.font_weight = "bold"
          t.content = layout[:title]
        end

        svg.add_element(text)
      end

      # Renders the grid lines.
      #
      # @param layout [Hash] layout data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_grid(layout, svg)
        plot_x = layout[:plot_x]
        plot_y = layout[:plot_y]
        plot_width = layout[:plot_width]
        plot_height = layout[:plot_height]

        # Horizontal grid lines (Y-axis)
        GRID_LINES.times do |i|
          y = plot_y + (i * plot_height / GRID_LINES)

          line = Svg::Line.new.tap do |l|
            l.x1 = plot_x
            l.y1 = y
            l.x2 = plot_x + plot_width
            l.y2 = y
            l.stroke = theme_color(:grid_line) || "#e5e7eb"
            l.stroke_width = "1"
            l.stroke_dasharray = "3,3"
          end

          svg.add_element(line)
        end

        # Vertical grid lines (X-axis) - only for categorical
        if layout[:x_axis][:type] == :categorical
          positions = layout[:x_axis][:positions] || []
          positions.each do |pos|
            x = plot_x + pos[:position]

            line = Svg::Line.new.tap do |l|
              l.x1 = x
              l.y1 = plot_y
              l.x2 = x
              l.y2 = plot_y + plot_height
              l.stroke = theme_color(:grid_line) || "#e5e7eb"
              l.stroke_width = "1"
              l.stroke_dasharray = "3,3"
            end

            svg.add_element(line)
          end
        end
      end

      # Renders the X and Y axes.
      #
      # @param layout [Hash] layout data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_axes(layout, svg)
        plot_x = layout[:plot_x]
        plot_y = layout[:plot_y]
        plot_width = layout[:plot_width]
        plot_height = layout[:plot_height]

        # X-axis
        x_axis_line = Svg::Line.new.tap do |l|
          l.x1 = plot_x
          l.y1 = plot_y + plot_height
          l.x2 = plot_x + plot_width
          l.y2 = plot_y + plot_height
          l.stroke = theme_color(:axis_line) || "#000000"
          l.stroke_width = "2"
        end

        svg.add_element(x_axis_line)

        # Y-axis
        y_axis_line = Svg::Line.new.tap do |l|
          l.x1 = plot_x
          l.y1 = plot_y
          l.x2 = plot_x
          l.y2 = plot_y + plot_height
          l.stroke = theme_color(:axis_line) || "#000000"
          l.stroke_width = "2"
        end

        svg.add_element(y_axis_line)
      end

      # Renders axis labels and ticks.
      #
      # @param layout [Hash] layout data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_axis_labels(layout, svg)
        render_x_axis_labels(layout, svg)
        render_y_axis_labels(layout, svg)
      end

      # Renders X-axis labels.
      #
      # @param layout [Hash] layout data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_x_axis_labels(layout, svg)
        plot_x = layout[:plot_x]
        plot_y = layout[:plot_y]
        plot_height = layout[:plot_height]

        x_axis = layout[:x_axis]

        # X-axis title
        if x_axis[:label]
          text = Svg::Text.new.tap do |t|
            t.x = plot_x + layout[:plot_width] / 2
            t.y = plot_y + plot_height + 60
            t.text_anchor = "middle"
            t.fill = theme_color(:label_text) || "#000000"
            t.font_size = (theme_typography(:font_size_normal) || 12).to_s
            t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
            t.font_weight = "bold"
            t.content = x_axis[:label]
          end

          svg.add_element(text)
        end

        # X-axis tick labels
        if x_axis[:type] == :categorical
          (x_axis[:positions] || []).each do |pos|
            x = plot_x + pos[:position]
            y = plot_y + plot_height + 20

            text = Svg::Text.new.tap do |t|
              t.x = x
              t.y = y
              t.text_anchor = "middle"
              t.fill = theme_color(:label_text) || "#000000"
              t.font_size = (theme_typography(:font_size_small) || 10).to_s
              t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
              t.content = pos[:label]
            end

            svg.add_element(text)
          end
        end
      end

      # Renders Y-axis labels.
      #
      # @param layout [Hash] layout data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_y_axis_labels(layout, svg)
        plot_x = layout[:plot_x]
        plot_y = layout[:plot_y]
        plot_height = layout[:plot_height]

        y_axis = layout[:y_axis]

        # Y-axis title
        if y_axis[:label]
          text = Svg::Text.new.tap do |t|
            t.x = 20
            t.y = plot_y + plot_height / 2
            t.text_anchor = "middle"
            t.fill = theme_color(:label_text) || "#000000"
            t.font_size = (theme_typography(:font_size_normal) || 12).to_s
            t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
            t.font_weight = "bold"
            t.transform = "rotate(-90, 20, #{plot_y + plot_height / 2})"
            t.content = y_axis[:label]
          end

          svg.add_element(text)
        end

        # Y-axis tick labels
        min = y_axis[:min]
        max = y_axis[:max]

        GRID_LINES.times do |i|
          y = plot_y + (i * plot_height / GRID_LINES)
          value = max - (i * (max - min) / GRID_LINES)

          text = Svg::Text.new.tap do |t|
            t.x = plot_x - 10
            t.y = y + 4
            t.text_anchor = "end"
            t.fill = theme_color(:label_text) || "#000000"
            t.font_size = (theme_typography(:font_size_small) || 10).to_s
            t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
            t.content = value.round(1).to_s
          end

          svg.add_element(text)
        end
      end

      # Renders all datasets.
      #
      # @param layout [Hash] layout data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_datasets(layout, svg)
        layout[:datasets].each_with_index do |dataset, idx|
          color = get_dataset_color(idx)

          case dataset[:chart_type]
          when :line
            render_line_dataset(dataset, color, layout, svg)
          when :bar
            render_bar_dataset(dataset, color, layout, svg)
          else
            render_line_dataset(dataset, color, layout, svg)
          end
        end
      end

      # Gets color for a dataset based on index.
      #
      # @param index [Integer] dataset index
      # @return [String] color value
      def get_dataset_color(index)
        DEFAULT_COLORS[index % DEFAULT_COLORS.length]
      end

      # Renders a line dataset.
      #
      # @param dataset [Hash] dataset data
      # @param color [String] line color
      # @param layout [Hash] layout data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_line_dataset(dataset, color, layout, svg)
        return if dataset[:points].empty?

        plot_x = layout[:plot_x]
        plot_y = layout[:plot_y]

        # Build polyline points
        points = dataset[:points].map do |point|
          x = plot_x + point[:x]
          y = plot_y + point[:y]
          "#{x},#{y}"
        end.join(" ")

        polyline = Svg::Polyline.new.tap do |p|
          p.points = points
          p.fill = "none"
          p.stroke = color
          p.stroke_width = "2"
        end

        svg.add_element(polyline)

        # Render data points as circles
        dataset[:points].each do |point|
          x = plot_x + point[:x]
          y = plot_y + point[:y]

          circle = Svg::Circle.new.tap do |c|
            c.cx = x
            c.cy = y
            c.r = 4
            c.fill = color
            c.stroke = theme_color(:background) || "#ffffff"
            c.stroke_width = "2"
          end

          svg.add_element(circle)
        end
      end

      # Renders a bar dataset.
      #
      # @param dataset [Hash] dataset data
      # @param color [String] bar color
      # @param layout [Hash] layout data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_bar_dataset(dataset, color, layout, svg)
        return if dataset[:points].empty?

        plot_x = layout[:plot_x]
        plot_y = layout[:plot_y]
        plot_height = layout[:plot_height]

        # Calculate bar width
        x_axis = layout[:x_axis]
        bar_width = if x_axis[:type] == :categorical && x_axis[:positions]
                      spacing = layout[:plot_width] / x_axis[:positions].length
                      spacing * BAR_WIDTH_RATIO
                    else
                      20
                    end

        # Render each bar
        dataset[:points].each do |point|
          x = plot_x + point[:x] - bar_width / 2
          y = plot_y + point[:y]
          height = plot_height - point[:y]

          rect = Svg::Rect.new.tap do |r|
            r.x = x
            r.y = y
            r.width = bar_width
            r.height = height
            r.fill = color
            r.fill_opacity = "0.8"
            r.stroke = color
            r.stroke_width = "1"
          end

          svg.add_element(rect)
        end
      end

      # Renders legend for all datasets.
      #
      # @param layout [Hash] layout data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_legend(layout, svg)
        return if layout[:datasets].empty?

        legend_x = layout[:width] - 150
        legend_y = 60
        item_height = 25

        layout[:datasets].each_with_index do |dataset, idx|
          color = get_dataset_color(idx)
          y_offset = idx * item_height

          # Color box
          rect = Svg::Rect.new.tap do |r|
            r.x = legend_x
            r.y = legend_y + y_offset - 8
            r.width = 15
            r.height = 15
            r.fill = color
            r.stroke = "none"
          end

          svg.add_element(rect)

          # Label
          text = Svg::Text.new.tap do |t|
            t.x = legend_x + 20
            t.y = legend_y + y_offset + 4
            t.text_anchor = "start"
            t.fill = theme_color(:label_text) || "#000000"
            t.font_size = (theme_typography(:font_size_small) || 10).to_s
            t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
            t.content = dataset[:label]
          end

          svg.add_element(text)
        end
      end
    end
  end
end