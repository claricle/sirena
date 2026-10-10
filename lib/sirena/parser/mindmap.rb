# frozen_string_literal: true

require_relative "base"
require_relative "grammars/mindmap"
require_relative "builders/mindmap"
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
    #   parser = Mindmap.new
    #   source = <<~MERMAID
    #     mindmap
    #       root((Central Idea))
    #         Branch 1
    #           Sub-item 1.1
    #         Branch 2
    #   MERMAID
    #   diagram = parser.parse(source)
    class Mindmap < Base
      grammar Grammars::Mindmap
      builder Builders::Mindmap

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
        result[:nodes].each do |node_data|
          next if node_data == result[:root]

          diagram.add_node(build_node(node_data))
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
          classes: node_data[:classes] || [],
        )

        node.parent = parent if parent

        # Build children recursively
        node_data[:children].each do |child_data|
          child = build_node(child_data, node)
          node.add_child(child)
        end

        node
      end
    end
  end
end
