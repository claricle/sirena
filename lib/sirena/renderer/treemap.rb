# frozen_string_literal: true

require_relative "base"
require_relative "../layout/treemap"
require_relative "../svg/document"
require_relative "../svg/rect"
require_relative "../svg/text"
require_relative "../svg/group"

module Sirena
  module Renderer
    # Renderer for treemap diagrams
    class Treemap < Base
      def render(layout)
        scene = typed_scene(layout)
        doc = create_document(scene)

        add_title(doc, scene.title) if scene.title

        scene.cells.each { |cell| render_cell(doc, cell) }

        doc
      end

      private

      def typed_scene(layout)
        return layout if layout.is_a?(Layout::Treemap::Scene)

        Layout::Treemap.from_graph(layout, theme: theme)
      end

      def add_title(doc, label)
        text = Svg::Text.new.tap do |t|
          t.content = label.text
          t.x = label.x
          t.y = label.y
          t.fill = theme_color(:label_text) || "#333"
          t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
          t.font_size = number_string(label.font_size)
          t.font_weight = label.font_weight
          t.text_anchor = label.text_anchor
        end
        doc << text
      end

      def render_cell(doc, cell, parent_group = nil)
        group = Svg::Group.new

        # Draw cell rectangle
        rect = Svg::Rect.new.tap do |r|
          r.x = cell.box.x
          r.y = cell.box.y
          r.width = cell.box.width
          r.height = cell.box.height
          r.fill = cell.fill
          r.stroke = cell.stroke
          r.stroke_width = "2"
          r.rx = cell.box.corner_radius
          r.ry = cell.box.corner_radius
        end
        group << rect

        # Add label
        group << label_element(cell.label)

        # Add value if it's a leaf
        group << label_element(cell.value_label) if cell.value_label

        # Render children recursively
        cell.children.each { |child| render_cell(group, child, group) }

        if parent_group
          parent_group << group
        else
          doc << group
        end
      end

      def label_element(label)
        Svg::Text.new.tap do |text|
          set_label_geometry(text, label)
          set_label_style(text, label)
        end
      end

      def set_label_geometry(text, label)
        text.content = label.text
        text.x = label.x
        text.y = label.y
      end

      def set_label_style(text, label)
        text.fill = theme_color(:label_text) || label_fallback(label)
        text.font_family = theme_typography(:font_family) || "Arial, sans-serif"
        text.font_size = number_string(label.font_size)
        text.font_weight = label.font_weight if label.font_weight
      end

      def label_fallback(label)
        label.style == "value" ? "#666" : "#333"
      end

      def number_string(value)
        value.to_i == value ? value.to_i.to_s : value.to_s
      end
    end
  end
end
