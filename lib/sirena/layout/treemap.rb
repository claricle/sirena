# frozen_string_literal: true

require_relative "base"
require_relative "../diagram/treemap"

module Sirena
  module Layout
    # Layout calculator for treemap diagrams
    class Treemap < Base
      PADDING = 10
      MIN_CELL_SIZE = 40
      LABEL_HEIGHT = 20
      HEADER_HEIGHT = 40

      DEPTH_COLORS = %w[#8dd3c7 #ffffb3 #bebada #fb8072].freeze

      class Box < Lutaml::Model::Serializable
        attribute :x, :float
        attribute :y, :float
        attribute :width, :float
        attribute :height, :float
        attribute :corner_radius, :float
      end

      class Label < Lutaml::Model::Serializable
        attribute :text, :string
        attribute :x, :float
        attribute :y, :float
        attribute :font_size, :float
        attribute :font_weight, :string
        attribute :text_anchor, :string
        attribute :style, :string
      end

      class Cell < Lutaml::Model::Serializable
        attribute :box, Box
        attribute :fill, :string
        attribute :stroke, :string
        attribute :label, Label
        attribute :value_label, Label
        attribute :children, Cell, collection: true, default: -> { [] }
      end

      class Scene < Layout::Scene
        attribute :view_box, :string
        attribute :title, Label
        attribute :cells, Cell, collection: true, default: -> { [] }
      end

      def self.from_graph(graph, theme: nil)
        layout = new
        layout.theme = theme if theme
        layout.send(:scene_from_graph, graph)
      end

      # Transforms the diagram into a layout structure.
      #
      # @param diagram [Diagram::Treemap] the treemap diagram
      # @return [Hash] layout data with positioned cells and dimensions
      def build_graph(diagram)
        total_value = diagram.total_value
        return default_layout(diagram) if total_value <= 0

        # Calculate dimensions
        width = calculate_width(diagram)
        height = calculate_height(diagram)
        y_offset = diagram.title ? HEADER_HEIGHT + PADDING : PADDING

        # Layout root nodes
        cells = []
        x = PADDING
        y = y_offset

        diagram.root_nodes.each do |node|
          cell = layout_node(node, x, y, width - 2 * PADDING,
                             height - y_offset - PADDING, total_value)
          cells << cell if cell
          y += cell[:height] + PADDING if cell
        end

        {
          width: width,
          height: height,
          title: diagram.title,
          cells: cells,
          class_defs: diagram.class_defs,
        }
      end

      private

      def scene(diagram)
        scene_from_graph(build_graph(diagram))
      end

      def scene_from_graph(graph)
        width = graph.fetch(:width)
        height = graph.fetch(:height)
        class_defs = graph[:class_defs] || {}
        Scene.new(
          width: width, height: height, view_box: "0 0 #{width} #{height}",
          title: title_label(graph[:title], width),
          cells: graph.fetch(:cells).map { |cell| typed_cell(cell, class_defs) }
        )
      end

      def title_label(title, width)
        return unless title

        Label.new(
          text: title, x: width / 2.0, y: 25, font_size: 18,
          font_weight: "bold", text_anchor: "middle", style: "title"
        )
      end

      def typed_cell(cell, class_defs)
        label_y = cell[:y] + 15
        Cell.new(
          box: cell_box(cell),
          fill: cell_fill_color(cell, class_defs),
          stroke: cell_stroke_color(cell, class_defs),
          label: cell_label(cell, label_y),
          value_label: value_label(cell, label_y),
          children: typed_children(cell, class_defs),
        )
      end

      def cell_box(cell)
        Box.new(
          x: cell[:x], y: cell[:y], width: cell[:width],
          height: cell[:height], corner_radius: 4
        )
      end

      def typed_children(cell, class_defs)
        cell[:children].map { |child| typed_cell(child, class_defs) }
      end

      def cell_label(cell, y_position)
        Label.new(
          text: truncate_label(cell[:label], cell[:width] - 10),
          x: cell[:x] + 5, y: y_position, font_size: 12,
          font_weight: "bold", style: "label"
        )
      end

      def value_label(cell, y_position)
        return unless cell[:value] && cell[:children].empty?

        Label.new(
          text: format_value(cell[:value]), x: cell[:x] + 5,
          y: y_position + 15, font_size: 10, style: "value"
        )
      end

      def cell_fill_color(cell, class_defs)
        style_value(cell, class_defs, :fill) ||
          DEPTH_COLORS[cell[:depth] % DEPTH_COLORS.length]
      end

      def cell_stroke_color(cell, class_defs)
        style_value(cell, class_defs, :stroke) ||
          theme.colors&.node_stroke || "#333"
      end

      def style_value(cell, class_defs, property)
        styles = class_defs[cell[:css_class]] if cell[:css_class]
        return unless styles

        match = styles.match(/#{property}:\s*([^;,]+)/)
        match[1].strip if match
      end

      def truncate_label(label, max_width)
        max_chars = (max_width / 7).to_i
        return label if label.length <= max_chars

        "#{label[0...(max_chars - 3)]}..."
      end

      def format_value(value)
        value == value.to_i ? value.to_i.to_s : format("%.1f", value)
      end

      def layout_node(node, x, y, available_width, available_height, total_value)
        node_value = node.total_value
        return nil if node_value <= 0

        # Calculate proportional height
        ratio = node_value / total_value
        height = [available_height * ratio, MIN_CELL_SIZE].max

        cell = {
          label: node.label,
          value: node_value,
          x: x,
          y: y,
          width: available_width,
          height: height,
          css_class: node.css_class,
          depth: node.depth,
          children: [],
        }

        # If this node has children, layout them recursively
        if node.branch? && node.children.any?
          child_y = y + LABEL_HEIGHT
          child_height = height - LABEL_HEIGHT - PADDING

          node.children.each do |child|
            child_cell = layout_node(child, x + PADDING, child_y,
                                     available_width - 2 * PADDING,
                                     child_height, node_value)
            if child_cell
              cell[:children] << child_cell
              child_y += child_cell[:height] + PADDING
            end
          end
        end

        cell
      end

      def calculate_width(diagram)
        # Base width calculation
        800
      end

      def calculate_height(diagram)
        # Calculate based on number of nodes
        node_count = count_nodes(diagram.root_nodes)
        base_height = 400
        additional_height = [node_count * 30, 200].min

        base_height + additional_height
      end

      def count_nodes(nodes)
        nodes.sum do |node|
          1 + (node.children ? count_nodes(node.children) : 0)
        end
      end

      def default_layout(diagram)
        {
          width: 800,
          height: 400,
          title: diagram.title,
          cells: [],
          class_defs: diagram.class_defs,
        }
      end
    end
  end
end
