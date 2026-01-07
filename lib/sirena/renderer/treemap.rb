# frozen_string_literal: true

require_relative 'base'
require_relative '../svg/document'
require_relative '../svg/rect'
require_relative '../svg/text'
require_relative '../svg/group'

module Sirena
  module Renderer
    # Renderer for treemap diagrams
    class Treemap < Base
      def render(layout)
        doc = Svg::Document.new(
          width: layout[:width],
          height: layout[:height]
        )

        # Add title if present
        if layout[:title]
          add_title(doc, layout[:title], layout[:width])
        end

        # Render all cells
        layout[:cells].each do |cell|
          render_cell(doc, cell, layout[:class_defs])
        end

        doc.to_xml
      end

      private

      def add_title(doc, title, width)
        text = Svg::Text.new.tap do |t|
          t.content = title
          t.x = width / 2
          t.y = 25
          t.fill = theme_color(:label_text) || '#333'
          t.font_family = theme_typography(:font_family) || 'Arial, sans-serif'
          t.font_size = '18'
          t.font_weight = 'bold'
          t.text_anchor = 'middle'
        end
        doc << text
      end

      def render_cell(doc, cell, class_defs, parent_group = nil)
        group = Svg::Group.new

        # Determine fill color based on depth and CSS class
        fill_color = cell_fill_color(cell, class_defs)
        stroke_color = cell_stroke_color(cell, class_defs)

        # Draw cell rectangle
        rect = Svg::Rect.new.tap do |r|
          r.x = cell[:x]
          r.y = cell[:y]
          r.width = cell[:width]
          r.height = cell[:height]
          r.fill = fill_color
          r.stroke = stroke_color
          r.stroke_width = '2'
          r.rx = 4
          r.ry = 4
        end
        group << rect

        # Add label
        label_y = cell[:y] + 15
        label = Svg::Text.new.tap do |t|
          t.content = truncate_label(cell[:label], cell[:width] - 10)
          t.x = cell[:x] + 5
          t.y = label_y
          t.fill = theme_color(:label_text) || '#333'
          t.font_family = theme_typography(:font_family) || 'Arial, sans-serif'
          t.font_size = '12'
          t.font_weight = 'bold'
        end
        group << label

        # Add value if it's a leaf
        if cell[:value] && cell[:children].empty?
          value_text = format_value(cell[:value])
          value_y = label_y + 15
          value_label = Svg::Text.new.tap do |t|
            t.content = value_text
            t.x = cell[:x] + 5
            t.y = value_y
            t.fill = theme_color(:label_text) || '#666'
            t.font_family = theme_typography(:font_family) || 'Arial, sans-serif'
            t.font_size = '10'
          end
          group << value_label
        end

        # Render children recursively
        cell[:children].each do |child|
          render_cell(group, child, class_defs, group)
        end

        if parent_group
          parent_group << group
        else
          doc << group
        end
      end

      def cell_fill_color(cell, class_defs)
        # If cell has a CSS class, try to extract fill from class_defs
        if cell[:css_class] && class_defs[cell[:css_class]]
          styles = class_defs[cell[:css_class]]
          if styles =~ /fill:\s*([^;,]+)/
            return $1.strip
          end
        end

        # Otherwise use default colors based on depth
        depth_colors = %w[#8dd3c7 #ffffb3 #bebada #fb8072]
        depth_colors[cell[:depth] % depth_colors.length]
      end

      def cell_stroke_color(cell, class_defs)
        # If cell has a CSS class, try to extract stroke from class_defs
        if cell[:css_class] && class_defs[cell[:css_class]]
          styles = class_defs[cell[:css_class]]
          if styles =~ /stroke:\s*([^;,]+)/
            return $1.strip
          end
        end

        theme_color(:node_stroke) || '#333'
      end

      def truncate_label(label, max_width)
        # Simple truncation - could be improved with actual text measurement
        max_chars = (max_width / 7).to_i
        return label if label.length <= max_chars

        "#{label[0...max_chars - 3]}..."
      end

      def format_value(value)
        if value == value.to_i
          value.to_i.to_s
        else
          format('%.1f', value)
        end
      end
    end
  end
end