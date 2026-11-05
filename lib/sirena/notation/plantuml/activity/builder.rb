# frozen_string_literal: true

require_relative "node"
require_relative "edge"
require_relative "note"
require_relative "diagram"
require_relative "../unsupported_construct_error"

module Sirena
  module Notation
    module PlantUML
      module Activity
        # Accumulates the nodes and edges both syntaxes parse into, and the
        # swimlane and partition a new node belongs to.
        class Builder
          attr_reader :nodes, :edges
          attr_accessor :title

          def initialize
            @nodes = []
            @edges = []
            @lanes = []
            @lane = nil
            @partition = nil
          end

          # @return [Node]
          def node(kind, text: nil, fill: nil, bare: false)
            Node.new(id: "n#{@nodes.size}", kind: kind, text: text,
                     fill: fill, bare: bare).tap { |n| enrol(n) }
          end

          # @return [Edge]
          def connect(from, to, **options)
            Edge.new(from: from, to: to, **options).tap { |e| @edges << e }
          end

          def lane(name, colour)
            @lanes << [name, colour] unless @lanes.any? { |n, _| n == name }
            @lane = name
          end

          # @param name [String, nil] nil leaves the partition
          def partition(name, line: 0, text: "")
            if name && @partition
              raise UnsupportedConstructError.new(
                construct: "nested partition", line: line, text: text,
              )
            end
            @partition = name
          end

          # @return [Diagram]
          def diagram
            Diagram.new(nodes: @nodes, edges: @edges, lanes: @lanes,
                        title: @title)
          end

          private

          def enrol(node)
            node.lane = @lane
            node.partition = @partition
            @nodes << node
          end
        end
      end
    end
  end
end
