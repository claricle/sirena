# frozen_string_literal: true

require "lutaml/model"
require_relative "base"

module Sirena
  module Diagram
    # Represents a node in a Sankey diagram.
    #
    # A node can be a source, target, or intermediate point in the flow.
    # Nodes are automatically discovered from flow definitions.
    class SankeyNode < Lutaml::Model::Serializable
      # Unique identifier for the node
      attribute :id, :string

      # Display label for the node (defaults to id if not set)
      attribute :label, :string

      def initialize(id = nil, label = nil)
        super()
        @id = id
        @label = label || id
      end

      # Validates the node has required attributes.
      #
      # @return [Boolean] true if node is valid
      def valid?
        !id.nil? && !id.empty?
      end

      # Get display label, falling back to id.
      #
      # @return [String] the label to display
      def display_label
        label && !label.empty? ? label : id
      end
    end

    # Represents a flow/link between two nodes in a Sankey diagram.
    #
    # A flow connects a source node to a target node with a value
    # that determines the width of the flow arrow.
    class SankeyFlow < Lutaml::Model::Serializable
      # Source node identifier
      attribute :source, :string

      # Target node identifier
      attribute :target, :string

      # Flow value (determines arrow width)
      attribute :value, :float

      # Optional label for the flow
      attribute :label, :string

      def initialize(source = nil, target = nil, value = 0.0)
        super()
        @source = source
        @target = target
        @value = value.to_f
      end

      # Validates the flow has required attributes.
      #
      # @return [Boolean] true if flow is valid
      def valid?
        !source.nil? && !source.empty? &&
          !target.nil? && !target.empty? &&
          value > 0
      end

      # Check if this is a self-loop.
      #
      # @return [Boolean] true if source equals target
      def self_loop?
        source == target
      end
    end

    # Sankey diagram model.
    #
    # Represents a Sankey diagram showing flows between nodes where
    # the width of arrows is proportional to flow values. Used for
    # visualizing energy flows, material flows, cost distributions, etc.
    #
    # @example Creating a Sankey diagram
    #   sankey = SankeyDiagram.new
    #   sankey.title = 'Energy Flow'
    #
    #   flow1 = SankeyFlow.new('Source', 'Process', 100)
    #   flow2 = SankeyFlow.new('Process', 'Output', 70)
    #   flow3 = SankeyFlow.new('Process', 'Waste', 30)
    #   sankey.flows << flow1 << flow2 << flow3
    class SankeyDiagram < Base
      # Collection of explicitly defined nodes (optional)
      attribute :nodes, SankeyNode, collection: true,
                default: -> { [] }

      # Collection of flows between nodes
      attribute :flows, SankeyFlow, collection: true,
                default: -> { [] }

      # Accessibility title (for screen readers)
      attribute :acc_title, :string

      # Accessibility description (for screen readers)
      attribute :acc_description, :string

      def initialize
        @nodes = []
        @flows = []
        super
      end

      # Returns the diagram type identifier.
      #
      # @return [Symbol] :sankey
      def diagram_type
        :sankey
      end

      # Validates the diagram structure.
      #
      # A Sankey diagram is valid if it has at least one flow.
      #
      # @return [Boolean] true if diagram is valid
      def valid?
        !flows.empty? && flows.all?(&:valid?)
      end

      # Get all unique node IDs from flows and explicit nodes.
      #
      # @return [Array<String>] array of unique node IDs
      def all_node_ids
        node_ids_from_flows = flows.flat_map { |f| [f.source, f.target] }
        explicit_node_ids = nodes.map(&:id)
        (node_ids_from_flows + explicit_node_ids).uniq
      end

      # Get or create node by ID.
      #
      # @param id [String] node identifier
      # @return [SankeyNode] the node
      def node_by_id(id)
        nodes.find { |n| n.id == id } || SankeyNode.new(id)
      end

      # Get all flows from a specific node.
      #
      # @param node_id [String] the source node ID
      # @return [Array<SankeyFlow>] flows from this node
      def flows_from(node_id)
        flows.select { |f| f.source == node_id }
      end

      # Get all flows to a specific node.
      #
      # @param node_id [String] the target node ID
      # @return [Array<SankeyFlow>] flows to this node
      def flows_to(node_id)
        flows.select { |f| f.target == node_id }
      end

      # Calculate total outflow from a node.
      #
      # @param node_id [String] the node ID
      # @return [Float] sum of all outgoing flow values
      def total_outflow(node_id)
        flows_from(node_id).sum(&:value)
      end

      # Calculate total inflow to a node.
      #
      # @param node_id [String] the node ID
      # @return [Float] sum of all incoming flow values
      def total_inflow(node_id)
        flows_to(node_id).sum(&:value)
      end

      # Get source nodes (nodes with no inflow).
      #
      # @return [Array<String>] source node IDs
      def source_nodes
        all_node_ids.select { |id| total_inflow(id).zero? }
      end

      # Get sink nodes (nodes with no outflow).
      #
      # @return [Array<String>] sink node IDs
      def sink_nodes
        all_node_ids.select { |id| total_outflow(id).zero? }
      end

      # Get total flow value in the diagram.
      #
      # @return [Float] sum of all flow values
      def total_flow
        flows.sum(&:value)
      end

      # Get maximum flow value.
      #
      # @return [Float] maximum single flow value
      def max_flow
        flows.map(&:value).max || 0.0
      end

      # Get minimum flow value.
      #
      # @return [Float] minimum single flow value
      def min_flow
        flows.map(&:value).min || 0.0
      end
    end
  end
end