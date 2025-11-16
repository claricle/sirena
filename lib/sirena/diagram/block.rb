# frozen_string_literal: true

require "lutaml/model"

module Sirena
  module Diagram
    # Represents a block in the diagram
    class Block < Lutaml::Model::Serializable
      attribute :id, :string
      attribute :label, :string
      attribute :width, :integer, default: -> { 1 }
      attribute :shape, :string, default: -> { "rect" }
      attribute :children, Block, collection: true, default: -> { [] }
      attribute :block_type, :string # "block", "space", "arrow"
      attribute :direction, :string # for arrow blocks: "up", "down", "left", "right"
      attribute :is_compound, :boolean, default: -> { false }

      def compound?
        is_compound
      end

      def space?
        block_type == "space"
      end

      def arrow?
        block_type == "arrow"
      end

      def add_child(child)
        children << child
        self.is_compound = true
      end
    end

    # Represents a connection between blocks
    class BlockConnection < Lutaml::Model::Serializable
      attribute :from, :string
      attribute :to, :string
      attribute :connection_type, :string # "arrow" or "line"
      attribute :label, :string

      def arrow?
        connection_type == "arrow"
      end

      def line?
        connection_type == "line"
      end
    end

    # Represents styling for a block
    class BlockStyle < Lutaml::Model::Serializable
      attribute :block_id, :string
      attribute :fill, :string
      attribute :stroke, :string
      attribute :stroke_width, :string
      attribute :properties, :string, collection: true, default: -> { [] }
    end

    # Represents a Mermaid block diagram
    class BlockDiagram < Lutaml::Model::Serializable
      attribute :columns, :integer, default: -> { 1 }
      attribute :blocks, Block, collection: true, default: -> { [] }
      attribute :connections, BlockConnection, collection: true, default: -> { [] }
      attribute :styles, BlockStyle, collection: true, default: -> { [] }

      def add_block(block)
        blocks << block
      end

      def add_connection(connection)
        connections << connection
      end

      def add_style(style)
        styles << style
      end
    end
  end
end