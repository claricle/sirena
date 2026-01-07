# frozen_string_literal: true

require_relative 'grammars/treemap'
require_relative 'transforms/treemap'
require_relative '../diagram/treemap'

module Sirena
  module Parser
    # Parser for treemap diagrams using Parslet
    class TreemapParser
      def initialize
        @grammar = Grammars::Treemap.new
        @transform = Transforms::Treemap.new
      end

      # Parse treemap source into a TreemapDiagram
      #
      # @param source [String] The treemap diagram source
      # @return [Diagram::TreemapDiagram] The parsed diagram
      # @raise [Parslet::ParseFailed] If parsing fails
      def parse(source)
        tree = @grammar.parse(source)
        intermediate = @transform.apply(tree)
        build_diagram(intermediate)
      rescue Parslet::ParseFailed => e
        raise ParseError, "Treemap parse error: #{e.message}"
      end

      private

      # Build TreemapDiagram from intermediate representation
      def build_diagram(data)
        diagram = Diagram::TreemapDiagram.new

        statements = data[:statements] || []
        nodes = []

        statements.each do |stmt|
          case stmt[:type]
          when :title
            diagram.title = stmt[:value]
          when :acc_title
            # Store accessibility title (could be added to base)
          when :acc_descr
            # Store accessibility description
          when :class_def
            diagram.add_class_def(stmt[:name], stmt[:styles])
          when :node
            nodes << stmt
          end
        end

        # Build hierarchical structure from flat node list
        build_hierarchy(diagram, nodes)

        diagram
      end

      # Build hierarchical tree from flat list of nodes with indentation
      def build_hierarchy(diagram, nodes)
        return if nodes.empty?

        # Stack to track the current parent at each indentation level
        # Format: [[indent_level, node], ...]
        stack = []

        nodes.each do |node_data|
          indent = node_data[:indent] || 0
          label = node_data[:label]
          value = node_data[:value]
          css_class = node_data[:css_class]

          # Create the node
          node = Diagram::TreemapNode.new(label, value)
          node.css_class = css_class if css_class

          # Pop stack until we find the parent
          stack.pop while stack.any? && stack.last[0] >= indent

          if stack.empty?
            # This is a root node
            diagram.add_root_node(node)
          else
            # This is a child of the last node in stack
            parent = stack.last[1]
            parent.add_child(node)
          end

          # Add current node to stack (it could be a parent for future nodes)
          stack.push([indent, node])
        end
      end
    end

    # Alias for backward compatibility
    Treemap = TreemapParser
  end
end