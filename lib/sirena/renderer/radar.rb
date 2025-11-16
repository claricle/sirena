# frozen_string_literal: true

require_relative "../svg/document"
require_relative "../svg/circle"
require_relative "../svg/line"
require_relative "../svg/polygon"
require_relative "../svg/text"
require_relative "../svg/group"

module Sirena
  module Renderer
    # Renders a Radar Chart layout to SVG.
    #
    # The renderer converts the positioned layout structure from
    # Transform::Radar into an SVG visualization showing:
    # - Circular or polygonal grid
    # - Radial axes from center
    # - Axis labels
    # - Data polygons for each curve/dataset
    # - Legend
    #
    # @example Render a radar chart
    #   renderer = Renderer::Radar.new(theme: my_theme)
    #   svg = renderer.render(layout)
    class Radar < Base
      # Default colors for datasets (cycling)
      DEFAULT_COLORS = %w[
        #2563eb #7c3aed #db2777 #ea580c #ca8a04
        #16a34a #0891b2 #4f46e5 #c026d3 #dc2626
      ].freeze

      # Renders the layout structure to SVG.
      #
      # @param layout [Hash] layout data from Transform::Radar
      # @return [Svg::Document] rendered SVG document
      def render(layout)
        svg = create_document_from_layout(layout)

        # Store center and radius for rendering
        @center_x = layout[:center_x]
        @center_y = layout[:center_y]
        @radius = layout[:radius]

        # Render in order: grid, axes, curves, labels, legend
        render_grid(layout, svg)
        render_axes(layout, svg)
        render_curves(layout, svg)
        render_axis_labels(layout, svg)
        render_legend(layout, svg) if should_show_legend?(layout)

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

      # Determines if legend should be shown.
      #
      # @param layout [Hash] layout data
      # @return [Boolean] true if legend should be shown
      def should_show_legend?(layout)
        # Check diagram options, default to true
        layout.dig(:options, :show_legend) != false
      end

      # Renders the grid (circular or polygonal).
      #
      # @param layout [Hash] layout data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_grid(layout, svg)
        layout[:grid_circles].each do |grid|
          render_grid_circle(grid, svg)
        end
      end

      # Renders a single grid circle.
      #
      # @param grid [Hash] grid circle data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_grid_circle(grid, svg)
        circle = Svg::Circle.new.tap do |c|
          c.cx = @center_x
          c.cy = @center_y
          c.r = grid[:radius]
          c.fill = "none"
          c.stroke = theme_color(:grid_line) || "#e5e7eb"
          c.stroke_width = "1"
        end

        svg.add_element(circle)
      end

      # Renders all axes radiating from center.
      #
      # @param layout [Hash] layout data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_axes(layout, svg)
        layout[:axes].each do |axis|
          render_axis_line(axis, svg)
        end
      end

      # Renders a single axis line.
      #
      # @param axis [Hash] axis data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_axis_line(axis, svg)
        line = Svg::Line.new.tap do |l|
          l.x1 = @center_x
          l.y1 = @center_y
          l.x2 = @center_x + axis[:end_x]
          l.y2 = @center_y + axis[:end_y]
          l.stroke = theme_color(:axis_line) || "#9ca3af"
          l.stroke_width = "1"
        end

        svg.add_element(line)
      end

      # Renders axis labels.
      #
      # @param layout [Hash] layout data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_axis_labels(layout, svg)
        layout[:axes].each do |axis|
          render_axis_label(axis, svg)
        end
      end

      # Renders a single axis label.
      #
      # @param axis [Hash] axis data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_axis_label(axis, svg)
        x = @center_x + axis[:label_x]
        y = @center_y + axis[:label_y]

        text = Svg::Text.new.tap do |t|
          t.x = x
          t.y = y
          t.text_anchor = calculate_text_anchor(axis[:angle_degrees])
          t.dominant_baseline = calculate_dominant_baseline(axis[:angle_degrees])
          t.fill = theme_color(:label_text) || "#000000"
          t.font_size = (theme_typography(:font_size_normal) || 12).to_s
          t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
          t.font_weight = "bold"
          t.content = axis[:label]
        end

        svg.add_element(text)
      end

      # Calculates text anchor based on angle.
      #
      # @param angle [Numeric] angle in degrees
      # @return [String] text anchor value
      def calculate_text_anchor(angle)
        # Normalize angle to 0-360
        normalized = angle % 360
        normalized += 360 if normalized < 0

        if normalized > 45 && normalized < 135
          "start"
        elsif normalized > 225 && normalized < 315
          "end"
        else
          "middle"
        end
      end

      # Calculates dominant baseline based on angle.
      #
      # @param angle [Numeric] angle in degrees
      # @return [String] dominant baseline value
      def calculate_dominant_baseline(angle)
        # Normalize angle to 0-360
        normalized = angle % 360
        normalized += 360 if normalized < 0

        if normalized > 135 && normalized < 225
          "hanging"
        elsif normalized < 45 || normalized > 315
          "auto"
        else
          "middle"
        end
      end

      # Renders all data curves as polygons.
      #
      # @param layout [Hash] layout data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_curves(layout, svg)
        layout[:curves].each_with_index do |curve, idx|
          color = get_curve_color(idx)
          render_curve_polygon(curve, color, svg)
        end
      end

      # Gets color for a curve based on index.
      #
      # @param index [Integer] curve index
      # @return [String] color value
      def get_curve_color(index)
        DEFAULT_COLORS[index % DEFAULT_COLORS.length]
      end

      # Renders a single curve as a polygon.
      #
      # @param curve [Hash] curve data
      # @param color [String] fill color
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_curve_polygon(curve, color, svg)
        return if curve[:points].empty?

        # Build points array for polygon
        points = curve[:points].map do |point|
          x = @center_x + point[:x]
          y = @center_y + point[:y]
          "#{x},#{y}"
        end.join(" ")

        polygon = Svg::Polygon.new.tap do |p|
          p.points = points
          p.fill = color
          p.fill_opacity = "0.3"
          p.stroke = color
          p.stroke_width = "2"
        end

        svg.add_element(polygon)

        # Render data points as small circles
        render_curve_points(curve, color, svg)
      end

      # Renders data points for a curve.
      #
      # @param curve [Hash] curve data
      # @param color [String] point color
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_curve_points(curve, color, svg)
        curve[:points].each do |point|
          x = @center_x + point[:x]
          y = @center_y + point[:y]

          circle = Svg::Circle.new.tap do |c|
            c.cx = x
            c.cy = y
            c.r = 3
            c.fill = color
            c.stroke = theme_color(:background) || "#ffffff"
            c.stroke_width = "1"
          end

          svg.add_element(circle)
        end
      end

      # Renders legend for all curves.
      #
      # @param layout [Hash] layout data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_legend(layout, svg)
        return if layout[:curves].empty?

        legend_x = 20
        legend_y = layout[:height] - 40
        item_height = 20

        layout[:curves].each_with_index do |curve, idx|
          color = get_curve_color(idx)
          y_offset = idx * item_height

          # Color box
          box = Svg::Circle.new.tap do |c|
            c.cx = legend_x
            c.cy = legend_y + y_offset
            c.r = 5
            c.fill = color
            c.stroke = "none"
          end

          svg.add_element(box)

          # Label
          text = Svg::Text.new.tap do |t|
            t.x = legend_x + 15
            t.y = legend_y + y_offset + 4
            t.text_anchor = "start"
            t.fill = theme_color(:label_text) || "#000000"
            t.font_size = (theme_typography(:font_size_small) || 10).to_s
            t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
            t.content = curve[:label]
          end

          svg.add_element(text)
        end
      end
    end
  end
end