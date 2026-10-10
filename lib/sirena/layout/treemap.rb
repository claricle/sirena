# frozen_string_literal: true

require_relative "base"
require_relative "treemap_placement"
require_relative "../diagram/treemap"
require_relative "../notation/mermaid/ir_adapters/treemap"

module Sirena
  module Layout
    # Layout calculator for treemap diagrams
    class Treemap < Base
      CANVAS_WIDTH = 1000
      CANVAS_HEIGHT = 400

      DEPTH_COLORS = %w[#8dd3c7 #ffffb3 #bebada #fb8072].freeze
      STYLE_PROPERTIES = {
        "fill_color" => :fill,
        "stroke_color" => :stroke,
      }.freeze
      private_constant :STYLE_PROPERTIES

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
        data = ir_data(diagram)
        hierarchy = partition_hierarchy(data)
        return default_layout(data) unless hierarchy[:total].positive?

        positioned_layout(data, hierarchy)
      end

      private

      def partition_hierarchy(data)
        partitions = data.series.select { |series| series.role == "partition" }
        roots = partitions.select { |partition| partition.parent_id.nil? }
        children = partitions.group_by(&:parent_id)
        context = { data: data, children: children }
        total = roots.sum { |root| partition_value(context, root) }
        { partitions: partitions, roots: roots, context: context, total: total }
      end

      def positioned_layout(data, hierarchy)
        context = hierarchy.fetch(:context)
        root = tree_root(hierarchy.fetch(:roots), context, hierarchy[:total])
        TreemapPlacement.call(root, CANVAS_WIDTH, CANVAS_HEIGHT)
        {
          width: CANVAS_WIDTH, height: CANVAS_HEIGHT, title: data.label,
          cells: root[:children].map { |node| cell_from(node, 0) },
          class_defs: class_definitions(data)
        }
      end

      def tree_root(roots, context, total)
        { value: total, children: tree_nodes(roots, context, 0) }
      end

      def tree_nodes(partitions, context, depth)
        nodes = partitions.filter_map { |part| tree_node(part, context, depth) }
        nodes.sort_by.with_index { |node, index| [-node[:value], index] }
      end

      def tree_node(partition, context, depth)
        value = partition_value(context, partition)
        return unless value.positive?

        kids = context.fetch(:children).fetch(partition.id, [])
        {
          label: partition.label, value: value, depth: depth,
          css_class: style_reference(context.fetch(:data), partition.id),
          children: tree_nodes(kids, context, depth + 1)
        }
      end

      def cell_from(node, depth)
        {
          label: node[:label], value: node[:value], depth: depth,
          x: node[:x0], y: node[:y0], css_class: node[:css_class],
          width: node[:x1] - node[:x0], height: node[:y1] - node[:y0],
          children: node[:children].map { |kid| cell_from(kid, depth + 1) }
        }
      end

      def ir_data(diagram)
        return diagram if diagram.is_a?(IR::Data)

        Notation::Mermaid::IRAdapters::Treemap.call(diagram)
      end

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
          text: cell[:label],
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
        return styles[property] if styles.is_a?(Hash)

        match = styles.match(/#{property}:\s*([^;,]+)/)
        match[1].strip if match
      end

      def format_value(value)
        value == value.to_i ? value.to_i.to_s : format("%.1f", value)
      end

      def partition_value(context, partition)
        data = context.fetch(:data)
        explicit = data.values.find do |value|
          value.role == "magnitude" && value.series_id == partition.id
        end
        return explicit.value.value if explicit

        context.fetch(:children).fetch(partition.id, []).sum do |child|
          partition_value(context, child)
        end
      end

      def style_reference(data, series_id)
        value = data.values.find do |entry|
          entry.role == "style_reference" && entry.series_id == series_id
        end
        value&.value&.value
      end

      def class_definitions(data)
        data.values.each_with_object({}) do |value, definitions|
          property = STYLE_PROPERTIES[value.role]
          next unless property

          definitions[value.label] ||= {}
          definitions[value.label][property] = value.value.value
        end
      end

      def default_layout(data)
        {
          width: CANVAS_WIDTH,
          height: CANVAS_HEIGHT,
          title: data.label,
          cells: [],
          class_defs: class_definitions(data),
        }
      end
    end
  end
end
