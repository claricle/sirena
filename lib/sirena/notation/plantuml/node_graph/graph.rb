# frozen_string_literal: true

require_relative "node"
require_relative "edge"

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # The nodes and links of one diagram, in source order.
        class Graph
          attr_reader :nodes, :edges
          attr_accessor :title, :direction

          # @param direction [Symbol] :left_to_right or :top_to_bottom
          def initialize(direction:)
            @direction = direction
            @nodes = {}
            @edges = []
            @title = nil
          end

          # @return [Node] the node for `id`, made with `kind` if new
          def node(id, kind, parent: nil)
            @nodes[id] ||= Node.new(id: id, kind: kind, parent: parent)
          end

          def find(name)
            @nodes[name] || @nodes.values.find { |n| n.lines == [name] }
          end

          # @return [Array<Node>] the nodes directly inside `parent`
          def children_of(parent)
            @nodes.values.select { |n| n.parent.equal?(parent) }
          end
        end
      end
    end
  end
end
