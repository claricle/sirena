# frozen_string_literal: true

require_relative "base"
require_relative "../diagram/sankey"

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
        @diagram = diagram
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
          acc_title: diagram.acc_title,
          acc_description: diagram.acc_description,
          nodes: typed_nodes,
          flows: typed_flows,
        )
      end

      private

      def assign_layers
        visited = Set.new
        source_nodes = @diagram.source_nodes

        source_nodes.each do |node_id|
          @node_layers[node_id] = 0
          visited.add(node_id)
        end

        queue = source_nodes.dup
        until queue.empty?
          current_id = queue.shift
          current_layer = @node_layers[current_id]

          @diagram.flows_from(current_id).each do |flow|
            target_id = flow.target
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

        @diagram.all_node_ids.each do |node_id|
          @node_layers[node_id] = 0 unless @node_layers.key?(node_id)
        end
      end

      def calculate_positions
        layers = Hash.new { |items, layer| items[layer] = [] }
        @node_layers.each { |node_id, layer| layers[layer] << node_id }

        layers.each do |layer, node_ids|
          sorted_nodes = node_ids.sort_by do |id|
            -(@diagram.total_inflow(id) + @diagram.total_outflow(id))
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
        total_flow = @diagram.total_inflow(node_id) +
                     @diagram.total_outflow(node_id)
        return MIN_NODE_WIDTH unless scalable_flow?(total_flow)

        ratio = total_flow / (@diagram.max_flow * 2)
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
        return unless @diagram.title

        Label.new(text: @diagram.title, x: width.to_i / 2, y: TITLE_Y)
      end

      def typed_nodes
        @diagram.nodes.map do |node|
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
              text: node.display_label,
              x: x + (width / 2),
              y: y + (height / 2) + NODE_LABEL_BASELINE_OFFSET,
            ),
            inflow: @diagram.total_inflow(node.id),
            outflow: @diagram.total_outflow(node.id),
          )
        end
      end

      def typed_flows
        colour_index = 0
        @diagram.flows.map.with_index do |flow, index|
          geometry = flow_geometry(flow)
          current_colour = colour_index
          colour_index += 1 unless flow.self_loop?

          Flow.new(
            id: "flow_#{index}",
            source: flow.source,
            target: flow.target,
            value: flow.value,
            width: geometry[:width],
            source_x: geometry[:source_x],
            source_y: geometry[:source_y],
            target_x: geometry[:target_x],
            target_y: geometry[:target_y],
            path: flow.self_loop? ? nil : flow_path(geometry),
            label: flow.self_loop? ? nil : flow_label(flow, geometry),
            colour_index: current_colour,
            self_loop: flow.self_loop?,
          )
        end
      end

      def flow_geometry(flow)
        source = @node_positions[flow.source]
        target = @node_positions[flow.target]
        {
          width: calculate_flow_width(flow.value),
          source_x: MARGIN_LEFT + source_edge(source),
          source_y: MARGIN_TOP + vertical_center(source),
          target_x: MARGIN_LEFT + target_edge(target),
          target_y: MARGIN_TOP + vertical_center(target),
        }
      end

      def calculate_flow_width(value)
        return 1 if @diagram.max_flow.zero?

        width = 2 + ((value / @diagram.max_flow) * 48)
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
        total_flow.positive? && @diagram.max_flow.positive?
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
        return unless flow.value.positive?

        Label.new(
          text: format_flow_value(flow.value),
          x: (geometry[:source_x] + geometry[:target_x]) / 2.0,
          y: (geometry[:source_y] + geometry[:target_y]) / 2.0,
        )
      end

      def format_flow_value(value)
        return value.to_i.to_s if value == value.to_i

        format("%.2f", value).gsub(/\.?0+$/, "")
      end
    end
  end
end
