# frozen_string_literal: true

require_relative 'base'

module Sirena
  module Diagram
    # Represents a treemap diagram showing hierarchical data
    class TreemapDiagram < Base
      attr_accessor :title, :root_nodes, :class_defs

      def initialize
        super
        @root_nodes = []
        @class_defs = {}
      end

      def type
        :treemap
      end

      # Add a root-level node
      def add_root_node(node)
        @root_nodes << node
      end

      # Add a class definition
      def add_class_def(name, styles)
        @class_defs[name] = styles
      end

      # Calculate total value of all nodes
      def total_value
        @root_nodes.sum(&:total_value)
      end
    end

    # Represents a node in a treemap (can be a branch or leaf)
    class TreemapNode
      attr_accessor :label, :value, :children, :css_class, :parent

      def initialize(label, value = nil)
        @label = label
        @value = value&.to_f
        @children = []
        @css_class = nil
        @parent = nil
      end

      # Add a child node
      def add_child(node)
        node.parent = self
        @children << node
      end

      # Check if this is a leaf node (has a value)
      def leaf?
        !@value.nil?
      end

      # Check if this is a branch node (has children)
      def branch?
        !@children.empty?
      end

      # Calculate total value including children
      def total_value
        if leaf?
          @value
        elsif branch?
          @children.sum(&:total_value)
        else
          0.0
        end
      end

      # Get the depth level of this node (root = 0)
      def depth
        return 0 unless @parent

        1 + @parent.depth
      end
    end
  end
end