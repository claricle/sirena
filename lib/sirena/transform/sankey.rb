# frozen_string_literal: true
require 'set'

require_relative "base"
require_relative "../diagram/sankey"

module Sirena
  module Transform
    # Sankey transformer for converting Sankey models to renderable structure.
    #
    # Handles layer assignment, node positioning, flow path calculation,
    # and flow width proportional to values.
    #
    # @example Transform a Sankey diagram
    #   transform = SankeyTransform.new
    #   data = transform.to_graph(sankey_diagram)
    class SankeyTransform < Base
      # Node height and spacing
      NODE_HEIGHT = 40
      NODE_SPACING = 30
      LAYER_SPACING = 150
      MIN_NODE_WIDTH = 20
      MAX_NODE_WIDTH = 40

      # Converts a Sankey diagram to a layout structure with calculated positions.
      #
      # @param diagram [Diagram::SankeyDiagram] the sankey diagram to transform
      # @return [Hash] data structure for rendering
      # @raise [TransformError] if diagram is invalid
      def to_graph(diagram)
        raise TransformError, "Invalid diagram" unless diagram.valid?

        @diagram = diagram
        @node_layers = {}
        @node_positions = {}

        # Assign nodes to layers (left to right)
        assign_layers

        # Calculate vertical positions within layers
        calculate_positions

        # Build transformation result
        {
          id: "sankey",
          title: diagram.title,
          acc_title: diagram.acc_title,
          acc_description: diagram.acc_description,
          nodes: transform_nodes,
          flows: transform_flows,
          metadata: {
            node_count: diagram.nodes.length,
            flow_count: diagram.flows.length,
            total_flow: diagram.total_flow,
            max_flow: diagram.max_flow,
            layer_count: @node_layers.values.max.to_i + 1
          }
        }
      end

      private

      def assign_layers
        # Use topological sorting to assign layers
        # Source nodes (no inflow) start at layer 0
        # Each subsequent layer is one step from previous

        visited = Set.new
        node_ids = @diagram.all_node_ids

        # Start with source nodes at layer 0
        source_nodes = @diagram.source_nodes
        source_nodes.each do |node_id|
          @node_layers[node_id] = 0
          visited.add(node_id)
        end

        # BFS to assign layers
        queue = source_nodes.dup
        while !queue.empty?
          current_id = queue.shift
          current_layer = @node_layers[current_id]

          # Process all flows from this node
          @diagram.flows_from(current_id).each do |flow|
            target_id = flow.target
            next if visited.include?(target_id)

            # Assign target to next layer
            target_layer = current_layer + 1
            @node_layers[target_id] = [
              @node_layers[target_id] || 0,
              target_layer
            ].max

            unless queue.include?(target_id)
              queue << target_id
              visited.add(target_id)
            end
          end
        end

        # Handle any nodes not reachable from sources (cycles, isolated nodes)
        node_ids.each do |node_id|
          unless @node_layers.key?(node_id)
            @node_layers[node_id] = 0
          end
        end
      end

      def calculate_positions
        # Group nodes by layer
        layers = Hash.new { |h, k| h[k] = [] }
        @node_layers.each do |node_id, layer|
          layers[layer] << node_id
        end

        # Calculate vertical positions for each layer
        layers.each do |layer_num, node_ids|
          # Sort nodes by total flow magnitude for better layout
          sorted_nodes = node_ids.sort_by do |id|
            -(@diagram.total_inflow(id) + @diagram.total_outflow(id))
          end

          # Position nodes vertically with spacing
          y_offset = 0
          sorted_nodes.each do |node_id|
            x = layer_num * LAYER_SPACING
            y = y_offset

            @node_positions[node_id] = {
              x: x,
              y: y,
              width: calculate_node_width(node_id),
              height: NODE_HEIGHT
            }

            y_offset += NODE_HEIGHT + NODE_SPACING
          end
        end
      end

      def calculate_node_width(node_id)
        # Node width proportional to flow through it
        total_flow = @diagram.total_inflow(node_id) +
                     @diagram.total_outflow(node_id)

        if total_flow > 0 && @diagram.max_flow > 0
          ratio = total_flow / (@diagram.max_flow * 2)
          width = MIN_NODE_WIDTH + (ratio * (MAX_NODE_WIDTH - MIN_NODE_WIDTH))
          width.round
        else
          MIN_NODE_WIDTH
        end
      end

      def transform_nodes
        @diagram.nodes.map do |node|
          position = @node_positions[node.id] || { x: 0, y: 0, width: MIN_NODE_WIDTH, height: NODE_HEIGHT }

          {
            id: node.id,
            label: node.display_label,
            layer: @node_layers[node.id] || 0,
            x: position[:x],
            y: position[:y],
            width: position[:width],
            height: position[:height],
            inflow: @diagram.total_inflow(node.id),
            outflow: @diagram.total_outflow(node.id)
          }
        end
      end

      def transform_flows
        @diagram.flows.map.with_index do |flow, index|
          source_pos = @node_positions[flow.source]
          target_pos = @node_positions[flow.target]

          # Calculate flow width proportional to value
          flow_width = calculate_flow_width(flow.value)

          {
            id: "flow_#{index}",
            source: flow.source,
            target: flow.target,
            value: flow.value,
            label: flow.label,
            width: flow_width,
            source_x: source_pos ? source_pos[:x] + source_pos[:width] : 0,
            source_y: source_pos ? source_pos[:y] + (source_pos[:height] / 2.0) : 0,
            target_x: target_pos ? target_pos[:x] : LAYER_SPACING,
            target_y: target_pos ? target_pos[:y] + (target_pos[:height] / 2.0) : 0,
            self_loop: flow.self_loop?
          }
        end
      end

      def calculate_flow_width(value)
        # Flow width proportional to value
        return 1 if @diagram.max_flow.zero?

        ratio = value / @diagram.max_flow
        min_width = 2
        max_width = 50

        width = min_width + (ratio * (max_width - min_width))
        [width.round, min_width].max
      end
    end
  end
end