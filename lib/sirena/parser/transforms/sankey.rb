# frozen_string_literal: true

require_relative "../../diagram/sankey"

module Sirena
  module Parser
    module Transforms
      # Transform for converting Parslet parse tree to Sankey diagram model.
      #
      # Converts the parse tree output from Grammars::Sankey into a
      # fully-formed Diagram::SankeyDiagram object with nodes and flows.
      class Sankey
        # Transform parse tree into Sankey diagram.
        #
        # @param tree [Array, Hash] Parslet parse tree
        # @return [Diagram::SankeyDiagram] the sankey diagram model
        def apply(tree)
          diagram = Diagram::SankeyDiagram.new

          # Tree structure: array with header and statements
          if tree.is_a?(Array)
            tree.each do |item|
              next unless item.is_a?(Hash)

              process_item(diagram, item)
            end
          elsif tree.is_a?(Hash)
            process_item(diagram, tree)

            if tree[:statements]
              process_statements(diagram, tree[:statements])
            end
          end

          # Auto-discover nodes from flows if not explicitly declared
          ensure_nodes_from_flows(diagram)

          diagram
        end

        private

        def process_item(diagram, item)
          return unless item.is_a?(Hash)

          process_header(diagram, item) if item.key?(:header)
          process_node_declaration(diagram, item) if item.key?(:node_declaration)
          process_flow_entry(diagram, item) if item.key?(:flow_entry)
        end

        def process_statements(diagram, statements)
          Array(statements).each do |stmt|
            process_item(diagram, stmt) if stmt.is_a?(Hash)
          end
        end

        def process_header(diagram, item)
          # Header is just the 'sankey-beta' keyword, nothing to extract
        end

        def process_node_declaration(diagram, item)
          node_data = item[:node_declaration]
          return unless node_data

          node_id = extract_text(node_data[:node_id])
          node_label = extract_text(node_data[:node_label])

          # Check if node already exists
          existing_node = diagram.nodes.find { |n| n.id == node_id }
          if existing_node
            # Update label if provided
            existing_node.label = node_label unless node_label.empty?
          else
            # Create new node
            node = Diagram::SankeyNode.new(node_id, node_label)
            diagram.nodes << node
          end
        end

        def process_flow_entry(diagram, item)
          flow_data = item[:flow_entry]
          return unless flow_data

          source = extract_text(flow_data[:source])
          target = extract_text(flow_data[:target])
          value_str = extract_text(flow_data[:value])
          value = value_str.to_f

          flow = Diagram::SankeyFlow.new(source, target, value)
          diagram.flows << flow
        end

        # Ensure all nodes referenced in flows exist in the nodes collection
        def ensure_nodes_from_flows(diagram)
          node_ids_from_flows = diagram.flows.flat_map do |flow|
            [flow.source, flow.target]
          end.uniq

          node_ids_from_flows.each do |node_id|
            # Check if node already exists
            unless diagram.nodes.any? { |n| n.id == node_id }
              # Create node with id as label
              node = Diagram::SankeyNode.new(node_id, node_id)
              diagram.nodes << node
            end
          end
        end

        def extract_text(value)
          case value
          when Hash
            value.values.first.to_s
          when String
            value
          else
            value.to_s
          end.strip
        end
      end
    end
  end
end