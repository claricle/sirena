# frozen_string_literal: true

require_relative "base"
require_relative "../diagram/sankey"
require_relative "../notation/mermaid/ir_adapters/sankey"

module Sirena
  module Layout
    # Computes final canvas geometry for Sankey diagrams.
    class Sankey < Base
      NODE_HEIGHT = 40
      NODE_SPACING = 30
      LAYER_SPACING = 150
      MIN_NODE_WIDTH = 20
      MAX_NODE_WIDTH = 40

      MARGIN_LEFT = 60
      MARGIN_TOP = 100
      MARGIN_RIGHT = 60
      MARGIN_BOTTOM = 60
      EXTRA_WIDTH = 100
      EMPTY_WIDTH = 400
      EMPTY_HEIGHT = 300
      TITLE_Y = 40
      NODE_LABEL_BASELINE_OFFSET = 5

      class Label < Lutaml::Model::Serializable
        attribute :text, :string
        attribute :x, :float
        attribute :y, :float
      end

      class Node < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :layer, :integer
        attribute :x, :float
        attribute :y, :float
        attribute :width, :float
        attribute :height, :float
        attribute :corner_radius, :float
        attribute :label, Label
        attribute :inflow, :float
        attribute :outflow, :float
      end

      class Flow < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :source, :string
        attribute :target, :string
        attribute :value, :float
        attribute :width, :float
        attribute :source_x, :float
        attribute :source_y, :float
        attribute :target_x, :float
        attribute :target_y, :float
        attribute :path, :string
        attribute :label, Label
        attribute :colour_index, :integer
        attribute :self_loop, :boolean, default: false
      end

      class Scene < Layout::Scene
        attribute :id, :string
        attribute :view_box, :string
        attribute :title, Label
        attribute :acc_title, :string
        attribute :acc_description, :string
        attribute :nodes, Node, collection: true, default: -> { [] }
        attribute :flows, Flow, collection: true, default: -> { [] }
      end

      def scene(diagram)
        @graph = ir_graph(diagram)
        @node_layers = {}
        @node_positions = {}

        assign_layers
        calculate_positions

        width = canvas_width
        height = canvas_height
        Scene.new(
          id: "sankey",
          width: width,
          height: height,
          view_box: "0 0 #{width} #{height}",
          title: title_geometry(width),
          acc_title: @graph.accessibility_title,
          acc_description: @graph.accessibility_description,
          nodes: typed_nodes,
          flows: typed_flows,
        )
      end

      private

      def ir_graph(diagram)
        return diagram if diagram.is_a?(IR::Graph)

        Notation::Mermaid::IRAdapters::Sankey.call(diagram)
      end

      def assign_layers
        visited = Set.new
        source_nodes = @graph.nodes.filter_map do |node|
          node.id if total_inflow(node.id).zero?
        end

        source_nodes.each do |node_id|
          @node_layers[node_id] = 0
          visited.add(node_id)
        end

        queue = source_nodes.dup
        until queue.empty?
          current_id = queue.shift
          current_layer = @node_layers[current_id]

          flows_from(current_id).each do |flow|
            target_id = flow.target_id
            next if visited.include?(target_id)

            @node_layers[target_id] = [
              @node_layers[target_id] || 0,
              current_layer + 1,
            ].max
            next if queue.include?(target_id)

            queue << target_id
            visited.add(target_id)
          end
        end

        @graph.nodes.each do |node|
          node_id = node.id
          @node_layers[node_id] = 0 unless @node_layers.key?(node_id)
        end
      end

      def calculate_positions
        layers = Hash.new { |items, layer| items[layer] = [] }
        @node_layers.each { |node_id, layer| layers[layer] << node_id }

        layers.each do |layer, node_ids|
          sorted_nodes = node_ids.sort_by do |id|
            -(total_inflow(id) + total_outflow(id))
          end

          sorted_nodes.each_with_index do |node_id, index|
            @node_positions[node_id] = {
              x: layer * LAYER_SPACING,
              y: index * (NODE_HEIGHT + NODE_SPACING),
              width: calculate_node_width(node_id),
              height: NODE_HEIGHT,
            }
          end
        end
      end

      def calculate_node_width(node_id)
        total_flow = total_inflow(node_id) + total_outflow(node_id)
        return MIN_NODE_WIDTH unless scalable_flow?(total_flow)

        ratio = total_flow / (max_flow * 2)
        width = MIN_NODE_WIDTH + (ratio * (MAX_NODE_WIDTH - MIN_NODE_WIDTH))
        width.round
      end

      def canvas_width
        return empty_canvas_width if @node_positions.empty?

        right_edge = @node_positions.values.map do |position|
          position[:x] + position[:width]
        end.max
        MARGIN_LEFT + right_edge + MARGIN_RIGHT + EXTRA_WIDTH
      end

      def canvas_height
        return empty_canvas_height if @node_positions.empty?

        bottom_edge = @node_positions.values.map do |position|
          position[:y] + position[:height]
        end.max
        MARGIN_TOP + bottom_edge + MARGIN_BOTTOM
      end

      def title_geometry(width)
        return unless @graph.label

        Label.new(text: @graph.label, x: width.to_i / 2, y: TITLE_Y)
      end

      def typed_nodes
        @graph.nodes.map do |node|
          position = @node_positions.fetch(
            node.id,
            { x: 0, y: 0, width: MIN_NODE_WIDTH, height: NODE_HEIGHT },
          )
          x = MARGIN_LEFT + position[:x]
          y = MARGIN_TOP + position[:y]
          width = position[:width]
          height = position[:height]

          Node.new(
            id: node.id,
            layer: @node_layers[node.id] || 0,
            x: x,
            y: y,
            width: width,
            height: height,
            corner_radius: 3,
            label: Label.new(
              text: node.label || node.id,
              x: x + (width / 2),
              y: y + (height / 2) + NODE_LABEL_BASELINE_OFFSET,
            ),
            inflow: total_inflow(node.id),
            outflow: total_outflow(node.id),
          )
        end
      end

      def typed_flows
        colour_index = 0
        @graph.edges.map do |flow|
          geometry = flow_geometry(flow)
          current_colour = colour_index
          colour_index += 1 unless self_loop?(flow)

          Flow.new(
            id: flow.id,
            source: flow.source_id,
            target: flow.target_id,
            value: flow.properties.weight,
            width: geometry[:width],
            source_x: geometry[:source_x],
            source_y: geometry[:source_y],
            target_x: geometry[:target_x],
            target_y: geometry[:target_y],
            path: self_loop?(flow) ? nil : flow_path(geometry),
            label: self_loop?(flow) ? nil : flow_label(flow, geometry),
            colour_index: current_colour,
            self_loop: self_loop?(flow),
          )
        end
      end

      def flow_geometry(flow)
        {
          width: calculate_flow_width(flow.properties.weight),
        }.merge(endpoint_geometry(flow))
      end

      def endpoint_geometry(flow)
        source = @node_positions[flow.source_id]
        target = @node_positions[flow.target_id]
        { source_x: MARGIN_LEFT + source_edge(source),
          source_y: MARGIN_TOP + vertical_center(source),
          target_x: MARGIN_LEFT + target_edge(target),
          target_y: MARGIN_TOP + vertical_center(target) }
      end

      def calculate_flow_width(value)
        return 1 if max_flow.zero?

        width = 2 + ((value / max_flow) * 48)
        [width.round, 2].max
      end

      def flow_path(geometry)
        source_top, target_top, source_bottom, target_bottom =
          flow_edges(geometry)

        [
          "M #{geometry[:source_x]} #{source_top}",
          curve_command(geometry, source_top, target_top),
          "L #{geometry[:target_x]} #{target_bottom}",
          curve_command(geometry, target_bottom, source_bottom, reverse: true),
          "Z",
        ].join(" ")
      end

      def flow_edges(geometry)
        half_width = geometry[:width] / 2.0
        [
          geometry[:source_y] - half_width,
          geometry[:target_y] - half_width,
          geometry[:source_y] + half_width,
          geometry[:target_y] + half_width,
        ]
      end

      def curve_command(geometry, source_y, target_y, reverse: false)
        offset = (geometry[:target_x] - geometry[:source_x]) * 0.5
        source_control = geometry[:source_x] + offset
        target_control = geometry[:target_x] - offset
        controls = [source_control, target_control]
        controls.reverse! if reverse
        end_x = reverse ? geometry[:source_x] : geometry[:target_x]

        [
          "C #{controls[0]} #{source_y},",
          "#{controls[1]} #{target_y},",
          "#{end_x} #{target_y}",
        ].join(" ")
      end

      def scalable_flow?(total_flow)
        total_flow.positive? && max_flow.positive?
      end

      def empty_canvas_width
        MARGIN_LEFT + MARGIN_RIGHT + EMPTY_WIDTH
      end

      def empty_canvas_height
        MARGIN_TOP + MARGIN_BOTTOM + EMPTY_HEIGHT
      end

      def source_edge(position)
        position ? position[:x] + position[:width] : 0
      end

      def target_edge(position)
        position ? position[:x] : LAYER_SPACING
      end

      def vertical_center(position)
        position ? position[:y] + (position[:height] / 2.0) : 0
      end

      def flow_label(flow, geometry)
        value = flow.properties.weight
        return unless value.positive?

        Label.new(
          text: format_flow_value(value),
          x: (geometry[:source_x] + geometry[:target_x]) / 2.0,
          y: (geometry[:source_y] + geometry[:target_y]) / 2.0,
        )
      end

      def format_flow_value(value)
        return value.to_i.to_s if value == value.to_i

        format("%.2f", value).gsub(/\.?0+$/, "")
      end

      def flows_from(node_id)
        @graph.edges.select { |flow| flow.source_id == node_id }
      end

      def total_inflow(node_id)
        @graph.edges.filter_map do |flow|
          flow.properties.weight if flow.target_id == node_id
        end.sum
      end

      def total_outflow(node_id)
        flows_from(node_id).sum { |flow| flow.properties.weight }
      end

      def max_flow
        @graph.edges.filter_map { |flow| flow.properties.weight }.max || 0.0
      end

      def self_loop?(flow)
        flow.source_id == flow.target_id
      end
    end
  end
end
