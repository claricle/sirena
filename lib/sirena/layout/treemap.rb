# frozen_string_literal: true

require_relative "base"
require_relative "../diagram/treemap"
require_relative "../notation/mermaid/ir_adapters/treemap"

module Sirena
  module Layout
    # Layout calculator for treemap diagrams
    class Treemap < Base
      PADDING = 10
      MIN_CELL_SIZE = 40
      LABEL_HEIGHT = 20
      HEADER_HEIGHT = 40

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
        roots = hierarchy.fetch(:roots)
        context = hierarchy.fetch(:context)
        total = hierarchy.fetch(:total)
        width = calculate_width(data)
        partitions = hierarchy.fetch(:partitions)
        height = calculate_height(partitions)
        title = data.label
        y_offset = title ? HEADER_HEIGHT + PADDING : PADDING
        bounds = canvas_bounds(
          PADDING, y_offset, width - 2 * PADDING,
          height - y_offset - PADDING
        )
        cells = root_cells(roots, context, total, bounds)
        definitions = class_definitions(data)

        {
          width: width, height: height, title: title,
          cells: cells, class_defs: definitions
        }
      end

      def canvas_bounds(x, y, width, height)
        { x: x, y: y, width: width, height: height }
      end

      def root_cells(roots, context, total, bounds)
        current_y = bounds.fetch(:y)
        roots.filter_map do |root|
          root_bounds = bounds.merge(y: current_y)
          cell = layout_partition(
            context, root, root_bounds, total, 0
          )
          current_y += cell[:height] + PADDING if cell
          cell
        end
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
        return styles[property] if styles.is_a?(Hash)

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

      def layout_partition(hierarchy_context, current_partition, available_bounds, parent_value, depth)
        node_value = partition_value(hierarchy_context, current_partition)
        return nil if node_value <= 0

        height = partition_height(available_bounds, node_value, parent_value)
        data = hierarchy_context.fetch(:data)
        label = current_partition.label
        partition_id = current_partition.id
        x_position = available_bounds.fetch(:x)
        y_position = available_bounds.fetch(:y)
        width = available_bounds.fetch(:width)
        css_class = style_reference(data, partition_id)
        cell = {
          label: label, value: node_value, x: x_position, y: y_position,
          width: width, height: height, css_class: css_class,
          depth: depth, children: []
        }
        children = partition_children(
          hierarchy_context, current_partition, cell, node_value, height, depth
        )
        cell[:children] = children
        cell
      end

      def partition_height(bounds, node_value, parent_value)
        ratio = node_value / parent_value
        [bounds.fetch(:height) * ratio, MIN_CELL_SIZE].max
      end

      def partition_children(context, partition, cell, parent_value, height,
                             depth)
        child_y = cell.fetch(:y) + LABEL_HEIGHT
        context.fetch(:children).fetch(partition.id, []).filter_map do |child|
          child_bounds = child_bounds(cell, child_y, height)
          child_cell = layout_partition(
            context, child, child_bounds, parent_value, depth + 1
          )
          child_y += child_cell[:height] + PADDING if child_cell
          child_cell
        end
      end

      def child_bounds(bounds, child_y_position, parent_height)
        {
          x: bounds.fetch(:x) + PADDING, y: child_y_position,
          width: bounds.fetch(:width) - 2 * PADDING,
          height: parent_height - LABEL_HEIGHT - PADDING
        }
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

      def calculate_width(_data)
        800
      end

      def calculate_height(partitions)
        base_height = 400
        additional_height = [partitions.size * 30, 200].min

        base_height + additional_height
      end

      def default_layout(data)
        {
          width: 800,
          height: 400,
          title: data.label,
          cells: [],
          class_defs: class_definitions(data),
        }
      end
    end
  end
end
