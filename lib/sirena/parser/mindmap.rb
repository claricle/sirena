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
        add_root(diagram, result[:root])
        add_remaining_nodes(diagram, result)
        diagram
      end

      def add_root(diagram, root_data)
        return unless root_data

        root = build_node(root_data)
        diagram.root = root
        diagram.add_node(root)
      end

      def add_remaining_nodes(diagram, result)
        result[:nodes].each do |node_data|
          next if node_data == result[:root]

          diagram.add_node(build_node(node_data))
        end
      end

      def build_node(node_data, parent = nil)
        node = create_node(node_data)
        node.parent = parent if parent
        add_children(node, node_data[:children])
        node
      end

      def create_node(node_data)
        Diagram::Mindmap::MindmapNode.new(
          id: node_data[:id],
          content: node_data[:content],
          level: node_data[:level],
          shape: node_data[:shape] || "default",
          icon: node_data[:icon],
          classes: node_data[:classes] || [],
        )
      end

      def add_children(node, children)
        children.each do |child_data|
          child = build_node(child_data, node)
          node.add_child(child)
        end
      end
    end
  end
end
