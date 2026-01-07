# frozen_string_literal: true

require 'lutaml/model'
require_relative 'base'

module Sirena
  module Diagram
    # Represents a flowchart node.
    #
    # A node has an identifier, label text, and a shape type that
    # determines how it should be rendered visually.
    class FlowchartNode < Lutaml::Model::Serializable
      # Unique identifier for the node
      attribute :id, :string

      # Display text/label for the node
      attribute :label, :string

      # Shape type: :rect, :rounded, :stadium, :subroutine, :cylindrical,
      # :circle, :asymmetric, :rhombus, :hexagon, :parallelogram,
      # :parallelogram_alt, :trapezoid, :trapezoid_alt, :double_circle
      attribute :shape, :string

      # Optional classes/styles
      attribute :classes, :string

      # Initialize with default shape
      def initialize(*args)
        super
        self.shape ||= 'rect'
      end

      # Validates the node has required attributes.
      #
      # @return [Boolean] true if node is valid
      def valid?
        !id.nil? && !id.empty? && !label.nil?
      end
    end

    # Represents a flowchart edge (connection between nodes).
    #
    # An edge connects a source node to a target node, with optional
    # label text and arrow styling.
    class FlowchartEdge < Lutaml::Model::Serializable
      # Source node identifier
      attribute :source_id, :string

      # Target node identifier
      attribute :target_id, :string

      # Optional edge label
      attribute :label, :string

      # Arrow type: :arrow, :dotted_arrow, :thick_arrow, :line,
      # :dotted_line, :thick_line
      attribute :arrow_type, :string

      # Initialize with default arrow type
      def initialize(*args)
        super
        self.arrow_type ||= 'arrow'
      end

      # Validates the edge has required attributes.
      #
      # @return [Boolean] true if edge is valid
      def valid?
        !source_id.nil? && !source_id.empty? &&
          !target_id.nil? && !target_id.empty?
      end
    end

    # Flowchart diagram model.
    #
    # Represents a complete flowchart with nodes and edges. Flowcharts
    # support various node shapes and edge types to create flow diagrams,
    # decision trees, and process flows.
    #
    # @example Creating a simple flowchart
    #   flowchart = Flowchart.new(direction: 'TD')
    #   flowchart.nodes << FlowchartNode.new(
    #     id: 'A',
    #     label: 'Start',
    #     shape: 'stadium'
    #   )
    #   flowchart.nodes << FlowchartNode.new(
    #     id: 'B',
    #     label: 'Process',
    #     shape: 'rect'
    #   )
    #   flowchart.edges << FlowchartEdge.new(
    #     source_id: 'A',
    #     target_id: 'B',
    #     arrow_type: 'arrow'
    #   )
    class Flowchart < Base
      # Collection of nodes in the flowchart
      attribute :nodes, FlowchartNode, collection: true, default: -> { [] }

      # Collection of edges connecting nodes
      attribute :edges, FlowchartEdge, collection: true, default: -> { [] }

      # Returns the diagram type identifier.
      #
      # @return [Symbol] :flowchart
      def diagram_type
        :flowchart
      end

      # Validates the flowchart structure.
      #
      # A flowchart is valid if:
      # - It has at least one node
      # - All nodes are valid
      # - All edges are valid
      # - All edge references point to existing nodes
      #
      # @return [Boolean] true if flowchart is valid
      def valid?
        return false if nodes.nil? || nodes.empty?
        return false unless nodes.all?(&:valid?)
        return false unless edges.nil? || edges.all?(&:valid?)

        # Validate edge references
        node_ids = nodes.map(&:id)
        edges&.each do |edge|
          return false unless node_ids.include?(edge.source_id)
          return false unless node_ids.include?(edge.target_id)
        end

        true
      end

      # Finds a node by its identifier.
      #
      # @param id [String] the node identifier to find
      # @return [FlowchartNode, nil] the node or nil if not found
      def find_node(id)
        nodes.find { |n| n.id == id }
      end

      # Finds all edges originating from a specific node.
      #
      # @param node_id [String] the source node identifier
      # @return [Array<FlowchartEdge>] edges from the node
      def edges_from(node_id)
        edges.select { |e| e.source_id == node_id }
      end

      # Finds all edges targeting a specific node.
      #
      # @param node_id [String] the target node identifier
      # @return [Array<FlowchartEdge>] edges to the node
      def edges_to(node_id)
        edges.select { |e| e.target_id == node_id }
      end
    end
  end
end
