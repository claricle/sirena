# frozen_string_literal: true

require_relative "base"
require_relative "grammars/mindmap"
require_relative "transforms/mindmap"
require_relative "../diagram/mindmap"

module Sirena
  module Parser
    # Mindmap parser for Mermaid mindmap diagram syntax.
    #
    # Uses Parslet grammar-based parsing to handle mindmap syntax
    # with hierarchical nodes, shapes, icons, and classes.
    #
    # Parses mindmaps with support for:
    # - Indentation-based hierarchy
    # - Multiple node shapes (circle, cloud, bang, hexagon, square)
    # - Icons (::icon(name))
    # - Classes (:::className)
    #
    # @example Parse a simple mindmap
    #   parser = MindmapParser.new
    #   source = <<~MERMAID
    #     mindmap
    #       root((Central Idea))
    #         Branch 1
    #           Sub-item 1.1
    #         Branch 2
    #   MERMAID
    #   diagram = parser.parse(source)
    class MindmapParser < Base
      # Parses mindmap diagram source into a Mindmap model.
      #
      # @param source [String] the Mermaid mindmap diagram source
      # @return [Diagram::Mindmap] the parsed mindmap diagram
      # @raise [ParseError] if syntax is invalid
      def parse(source)
        grammar = Grammars::Mindmap.new

        begin
          parse_tree = grammar.parse(source)
        rescue Parslet::ParseFailed => e
          raise ParseError, "Syntax error at #{e.parse_failure_cause.pos}: " \
                           "#{e.parse_failure_cause}"
        end

        # Transform parse tree to diagram model
        transform = Transforms::Mindmap.new
        result = transform.apply(parse_tree)

        # Create the diagram model
        create_diagram(result)
      end

      private

      def create_diagram(result)
        diagram = Diagram::Mindmap.new

        # Build node hierarchy
        if result[:root]
          root = build_node(result[:root])
          diagram.root = root
          diagram.add_node(root)
        end

        # Add all nodes to diagram
        result[:nodes]&.each do |node_data|
          next if node_data == result[:root]
          node = find_or_create_node(diagram, node_data)
          diagram.add_node(node) unless diagram.nodes.include?(node)
        end

        diagram
      end

      def build_node(node_data, parent = nil)
        node = Diagram::Mindmap::MindmapNode.new(
          id: node_data[:id],
          content: node_data[:content],
          level: node_data[:level],
          shape: node_data[:shape] || "default",
          icon: node_data[:icon],
          classes: node_data[:classes] || []
        )

        node.parent = parent if parent

        # Build children recursively
        node_data[:children]&.each do |child_data|
          child = build_node(child_data, node)
          node.add_child(child)
        end

        node
      end

      def find_or_create_node(diagram, node_data)
        existing = diagram.nodes.find { |n| n.id == node_data[:id] }
        return existing if existing

        build_node(node_data)
      end
    end
  end
end