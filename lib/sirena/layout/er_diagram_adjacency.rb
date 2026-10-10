# frozen_string_literal: true

module Sirena
  module Layout
    # The neighbours of every node in a chain of edges, in edge order.
    class ErDiagramAdjacency
      attr_reader :successors, :predecessors

      # @param edges [Array<Array(String, String)>] [from, to] pairs
      def initialize(edges)
        @successors = Hash.new { |hash, key| hash[key] = [] }
        @predecessors = Hash.new { |hash, key| hash[key] = [] }
        edges.each do |from, to|
          @successors[from] << to
          @predecessors[to] << from
        end
      end
    end
  end
end
