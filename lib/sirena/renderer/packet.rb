# frozen_string_literal: true

require_relative "../svg/document"
require_relative "../svg/rect"
require_relative "../svg/text"
require_relative "../svg/line"
require_relative "../svg/group"

module Sirena
  module Renderer
    # Renders a Packet Diagram layout to SVG.
    #
    # The renderer converts the positioned layout structure from
    # Transform::Packet into an SVG visualization showing:
    # - Packet grid with bit position markers
    # - Fields as labeled cells spanning correct bit ranges
    # - Row-based layout (typically 32 bits per row)
    # - Field labels
    #
    # @example Render a packet diagram
    #   renderer = Renderer::Packet.new(theme: my_theme)
    #   svg = renderer.render(layout)
    class Packet < Base
      # Renders the layout structure to SVG.
      #
      # @param layout [Hash] layout data from Transform::Packet
      # @return [Svg::Document] rendered SVG document
      def render(layout)
        svg = create_document_from_layout(layout)

        # Store layout parameters for rendering
        @layout = layout
        @title_offset = layout[:title_height] + layout[:title_margin]

        # Render components in order
        render_title(layout, svg) if layout[:title]
        render_bit_markers(layout, svg)
        render_grid_lines(layout, svg)
        render_fields(layout, svg)

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

      # Renders the diagram title.
      #
      # @param layout [Hash] layout data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_title(layout, svg)
        return unless layout[:title]

        text = Svg::Text.new.tap do |t|
          t.x = layout[:width] / 2
          t.y = layout[:padding] + (layout[:title_height] / 2)
          t.text_anchor = "middle"
          t.dominant_baseline = "middle"
          t.fill = theme_color(:title_text) || "#000000"
          t.font_size = (theme_typography(:font_size_large) || 16).to_s
          t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
          t.font_weight = "bold"
          t.content = layout[:title]
        end

        svg.add_element(text)
      end

      # Renders bit position markers at the top of each column.
      #
      # @param layout [Hash] layout data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_bit_markers(layout, svg)
        bits_per_row = layout[:bits_per_row]
        cell_width = layout[:cell_width]
        padding = layout[:padding]

        layout[:row_count].times do |row|
          bits_per_row.times do |bit_in_row|
            bit_number = (row * bits_per_row) + bit_in_row

            x = padding + (bit_in_row * cell_width) + (cell_width / 2)
            y = padding + @title_offset + (layout[:header_height] / 2) + \
                (row * layout[:cell_height])

            text = Svg::Text.new.tap do |t|
              t.x = x
              t.y = y
              t.text_anchor = "middle"
              t.dominant_baseline = "middle"
              t.fill = theme_color(:label_text) || "#666666"
              t.font_size = (theme_typography(:font_size_small) || 10).to_s
              t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
              t.content = bit_number.to_s
            end

            svg.add_element(text)
          end
        end
      end

      # Renders the packet grid lines.
      #
      # @param layout [Hash] layout data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_grid_lines(layout, svg)
        padding = layout[:padding]
        cell_width = layout[:cell_width]
        cell_height = layout[:cell_height]
        header_height = layout[:header_height]
        bits_per_row = layout[:bits_per_row]
        row_count = layout[:row_count]

        grid_width = bits_per_row * cell_width
        grid_height = row_count * cell_height

        # Vertical lines (bit boundaries)
        (bits_per_row + 1).times do |i|
          x = padding + (i * cell_width)
          y1 = padding + @title_offset + header_height
          y2 = y1 + grid_height

          line = Svg::Line.new.tap do |l|
            l.x1 = x
            l.y1 = y1
            l.x2 = x
            l.y2 = y2
            l.stroke = theme_color(:grid_line) || "#cccccc"
            l.stroke_width = "1"
          end

          svg.add_element(line)
        end

        # Horizontal lines (row boundaries)
        (row_count + 1).times do |i|
          y = padding + @title_offset + header_height + (i * cell_height)
          x1 = padding
          x2 = x1 + grid_width

          line = Svg::Line.new.tap do |l|
            l.x1 = x1
            l.y1 = y
            l.x2 = x2
            l.y2 = y
            l.stroke = theme_color(:grid_line) || "#cccccc"
            l.stroke_width = "1"
          end

          svg.add_element(line)
        end
      end

      # Renders all packet fields.
      #
      # @param layout [Hash] layout data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_fields(layout, svg)
        layout[:fields].each do |field|
          render_field(field, layout, svg)
        end
      end

      # Renders a single packet field.
      #
      # @param field [Hash] field data
      # @param layout [Hash] layout data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_field(field, layout, svg)
        # Adjust y position for title offset
        y = field[:y] + @title_offset

        # Draw field background
        rect = Svg::Rect.new.tap do |r|
          r.x = field[:x]
          r.y = y
          r.width = field[:width]
          r.height = field[:height]
          r.fill = theme_color(:field_background) || "#e0f2fe"
          r.stroke = theme_color(:field_border) || "#0284c7"
          r.stroke_width = "1.5"
        end

        svg.add_element(rect)

        # Draw field label
        label_x = field[:x] + (field[:width] / 2)
        label_y = y + (field[:height] / 2)

        text = Svg::Text.new.tap do |t|
          t.x = label_x
          t.y = label_y
          t.text_anchor = "middle"
          t.dominant_baseline = "middle"
          t.fill = theme_color(:field_text) || "#000000"
          t.font_size = (theme_typography(:font_size_normal) || 12).to_s
          t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
          t.content = field[:label]
        end

        svg.add_element(text)

        # Add bit range annotation if field is large enough
        if field[:width] > 100
          range_text = "#{field[:bit_start]}-#{field[:bit_end]}"

          range = Svg::Text.new.tap do |t|
            t.x = label_x
            t.y = label_y + 16
            t.text_anchor = "middle"
            t.dominant_baseline = "middle"
            t.fill = theme_color(:label_text) || "#666666"
            t.font_size = (theme_typography(:font_size_small) || 9).to_s
            t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
            t.content = range_text
          end

          svg.add_element(range)
        end
      end
    end
  end
end