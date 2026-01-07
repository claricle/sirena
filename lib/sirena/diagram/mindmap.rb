# frozen_string_literal: true

require "lutaml/model"

module Sirena
  module Diagram
    # Represents a Mindmap diagram
    class Mindmap < Base
      # Represents a node in the mindmap
      class MindmapNode < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :content, :string
        attribute :level, :integer, default: -> { 0 }
        attribute :shape, :string, default: -> { "default" }
        attribute :icon, :string
        attribute :classes, :string, collection: true, default: -> { [] }
        attribute :children, MindmapNode, collection: true, default: -> { [] }
        attribute :parent, MindmapNode

        # Shape constants
        SHAPES = {
          circle: "circle",       # ((text))
          cloud: "cloud",         # )text(
          bang: "bang",           # ))text((
          hexagon: "hexagon",     # {{text}}
          square: "square",       # [text]
          default: "default"      # plain text (rounded rectangle)
        }.freeze

        def add_child(child)
          child.parent = self
          child.level = level + 1
          children << child
        end

        def root?
          level == 0
        end

        def leaf?
          children.empty?
        end
      end

      attribute :root, MindmapNode
      attribute :nodes, MindmapNode, collection: true, default: -> { [] }

      def add_node(node)
        nodes << node
        @root = node if node.root?
      end
    end
  end
end