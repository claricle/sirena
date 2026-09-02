# frozen_string_literal: true

require_relative 'base'
require_relative '../diagram/flowchart'

module Sirena
  module Transform
    # Flowchart transformer for converting flowchart models to graphs.
    #
    # Converts a typed flowchart diagram model into a generic graph structure
    # suitable for layout computation by elkrb. Handles node dimension
    # calculation, edge mapping, and layout configuration.
    #
    # @example Transform a flowchart
    #   transform = FlowchartTransform.new
    #   graph = transform.to_graph(flowchart_diagram)
    class FlowchartTransform < Base
      # Default font size for text measurement
      DEFAULT_FONT_SIZE = 14

      # Converts a flowchart diagram to a graph structure.
      #
      # @param diagram [Diagram::Flowchart] the flowchart to transform
      # @return [Hash] elkrb-compatible graph hash
      # @raise [TransformError] if diagram is invalid
      def to_graph(diagram)
        raise TransformError, 'Invalid diagram' unless diagram.valid?

        {
          id: diagram.id || 'flowchart',
          children: transform_children(diagram),
          edges: transform_edges(diagram),
          layoutOptions: layout_options(diagram)
        }
      end

      private

      # Subgraphs become compound children holding their members, which is
      # what elkrb reads and what lets the layout size a cluster to fit.
      # A node in no subgraph stays at the top level.
      def transform_children(diagram)
        boxes = drawable_subgraphs(diagram)
        nested = boxes.each_with_object({}) do |box, acc|
          box.node_ids.each { |id| acc[id] = box }
        end

        placed = diagram.nodes.map { |node| transform_node(node) }

        assemble(boxes, placed, nested)
      end

      # Model order is kept for emitted clusters. Nested clusters are attached
      # before member nodes, so every cluster lists boxes before nodes. Parent
      # lookup is independent of declaration order, so a later cluster can
      # hold an earlier one.
      def assemble(boxes, placed, nested)
        entries = boxes.map { |box| [box, transform_subgraph(box)] }
        clusters_by_box = index_by_box(entries)
        parents_by_id = entries.to_h { |box, cluster| [box.id, cluster] }

        attach_clusters(entries, parents_by_id)
        loose = place_nodes(placed, nested, clusters_by_box)
        loose + root_clusters(entries, parents_by_id)
      end

      def index_by_box(entries)
        entries.each_with_object({}.compare_by_identity) do |(box, cluster), acc|
          acc[box] = cluster
        end
      end

      def attach_clusters(entries, parents)
        entries.each do |box, mine|
          holder = holder_of(box, parents)
          next unless holder

          holder.fetch(:children).push(mine)
        end
      end

      def root_clusters(entries, parents)
        entries.reject { |box, _cluster| holder_of(box, parents) }.map(&:last)
      end

      def place_nodes(nodes, nested, clusters)
        nodes.each_with_object([]) do |node, loose|
          holder = clusters[nested[node[:id]]]
          holder ? holder[:children] << node : loose << node
        end
      end

      # A box naming a parent nobody drew belongs at the top level. Asked
      # rather than written back, because the diagram belongs to the
      # caller and a transform has no business editing it.
      def holder_of(box, clusters)
        clusters[box.parent_id]
      end

      # An empty subgraph draws no cluster in mermaid, so it is not
      # carried into the layout.
      def drawable_subgraphs(diagram)
        (diagram.subgraphs || []).select(&:drawable?)
      end

      def transform_subgraph(box)
        label = measure_text(box.title, font_size: DEFAULT_FONT_SIZE)

        {
          id: box.id,
          width: 0,
          height: 0,
          children: [],
          labels: [
            { text: box.title, width: label[:width], height: label[:height] }
          ],
          metadata: { cluster: true }
        }
      end

      def transform_node(node)
        dims = calculate_dimensions(node)

        {
          id: node.id,
          width: dims[:width],
          height: dims[:height],
          labels: [
            {
              text: node.label,
              width: dims[:label_width],
              height: dims[:label_height]
            }
          ],
          metadata: {
            shape: node.shape,
            classes: node.classes
          }
        }
      end

      def transform_edges(diagram)
        return [] if diagram.edges.nil? || diagram.edges.empty?

        diagram.edges.map do |edge|
          {
            id: "#{edge.source_id}_to_#{edge.target_id}",
            sources: [edge.source_id],
            targets: [edge.target_id],
            labels: edge_labels(edge),
            metadata: {
              arrow_type: edge.arrow_type
            }
          }
        end
      end

      def edge_labels(edge)
        return [] if edge.label.nil? || edge.label.empty?

        label_dims = measure_text(edge.label, font_size: DEFAULT_FONT_SIZE)

        [
          {
            text: edge.label,
            width: label_dims[:width],
            height: label_dims[:height]
          }
        ]
      end

      def calculate_dimensions(node)
        label_dims = measure_text(
          node.label,
          font_size: DEFAULT_FONT_SIZE
        )

        node_dims = calculate_node_dimensions(
          label_dims[:width],
          label_dims[:height],
          shape_to_type(node.shape)
        )

        {
          width: node_dims[:width],
          height: node_dims[:height],
          label_width: label_dims[:width],
          label_height: label_dims[:height]
        }
      end

      def shape_to_type(shape)
        case shape
        when 'rect', 'subroutine'
          :rect
        when 'circle', 'double_circle'
          :circle
        when 'rhombus', 'hexagon'
          :diamond
        else
          :rect
        end
      end

      def layout_options(diagram)
        direction = direction_to_layout(diagram.direction)

        # Flowcharts use layered algorithm for hierarchical flow
        # This ensures nodes are placed in distinct layers and edges flow
        # in the specified direction with minimal crossings
        build_elk_options(
          algorithm: ALGORITHM_LAYERED,
          direction: direction,
          # Additional flowchart-specific options
          ElkOptions::NODE_NODE_SPACING => 50,
          ElkOptions::LAYER_SPACING => 50,
          ElkOptions::EDGE_NODE_SPACING => 30,
          ElkOptions::EDGE_EDGE_SPACING => 20,
          # SIMPLE node placement for predictable, straightforward layouts
          # This is ideal for flowcharts where clarity is paramount
          ElkOptions::NODE_PLACEMENT => 'SIMPLE'
        )
      end

      def direction_to_layout(direction)
        case direction
        when 'TD', 'TB'
          DIRECTION_DOWN
        when 'LR'
          DIRECTION_RIGHT
        when 'RL'
          DIRECTION_LEFT
        when 'BT'
          DIRECTION_UP
        else
          DIRECTION_DOWN # Default direction
        end
      end
    end
  end
end
