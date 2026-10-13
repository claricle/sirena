# frozen_string_literal: true

require_relative "base"
require_relative "../layout/treemap"
require_relative "../svg/document"
require_relative "../svg/rect"
require_relative "../svg/text"
require_relative "../svg/group"
require_relative "treemap/section_total"

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
        doc << Svg::Text.new.tap do |text|
          set_title_geometry(text, label)
          set_title_style(text, label)
        end
      end

      def set_title_geometry(text, label)
        text.content = label.text
        text.x = label.x
        text.y = label.y
        text.text_anchor = label.text_anchor
      end

      def set_title_style(text, label)
        text.fill = label_fill("#333")
        text.font_family = theme_typography(:font_family) || "Arial, sans-serif"
        text.font_size = number_string(label.font_size)
        text.font_weight = label.font_weight
      end

      def render_cell(doc, cell, parent_group = nil)
        group = cell_group(cell)
        cell.children.each { |child| render_cell(group, child, group) }
        (parent_group || doc) << group
      end

      def cell_group(cell)
        Svg::Group.new.tap do |group|
          group << cell_box(cell)
          group << label_element(cell.label)
          group << label_element(cell.value_label) if cell.value_label
          add_section_total(group, cell)
        end
      end

      def cell_box(cell)
        Svg::Rect.new.tap do |rect|
          set_cell_box_geometry(rect, cell.box)
          rect.fill = cell.fill
          rect.stroke = cell.stroke
          rect.stroke_width = "2"
        end
      end

      def set_cell_box_geometry(rect, box)
        rect.x = box.x
        rect.y = box.y
        rect.width = box.width
        rect.height = box.height
        rect.rx = box.corner_radius
        rect.ry = box.corner_radius
      end

      def add_section_total(group, cell)
        return unless cell.total_label&.text

        group << label_element(cell.total_label)
      end

      def label_element(label, content: label.text)
        Svg::Text.new.tap do |text|
          set_label_geometry(text, label, content)
          set_label_style(text, label)
        end
      end

      def set_label_geometry(text, label, content)
        text.content = content
        text.x = label.x
        text.y = label.y
        text.text_anchor = label.text_anchor if label.text_anchor
      end

      def set_label_style(text, label)
        text.fill = label_fill(label_fallback(label))
        text.font_family = theme_typography(:font_family) || "Arial, sans-serif"
        text.font_size = number_string(label.font_size)
        text.font_weight = label.font_weight if label.font_weight
      end

      def label_fill(fallback)
        theme ? theme_color(:label_text) : fallback
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
