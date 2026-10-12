# frozen_string_literal: true

module Sirena
  module Layout
    class Flowchart < Base
      # dagre's layering of a level with an edge that skips a row or points
      # back up. A back edge is turned to point down, as dagre's acyclic
      # step does, and every edge becomes a chain of stand-ins through the
      # layers it crosses: one between each pair of rows, as for an edge
      # label, and one in each row it passes.
      #
      # dagre ranks a node as near its successors as edge length allows, so
      # a node with as many edges in as out sits just above the nearest one,
      # where elkrb leaves it just below its predecessor.
      class EdgeChains
        attr_reader :ranks, :layers, :links, :dummies

        # @param ranks [Hash] box id => row, top row 0, as elkrb placed it
        # @param ends [Array<Array>] [upper, lower, turned] per edge
        # @param order [Array] box ids left to right as elkrb placed them
        def initialize(ranks, ends, order)
          @ranks = ranks.dup
          @ends = ends
          @links = []
          @dummies = []
          sink
          @layers = sweep(stacked(order))
        end

        private

        def sink
          @ranks.keys.sort_by { |id| -@ranks[id] }.each do |id|
            below = @ends.filter_map { |upper, lower, _| @ranks[lower] if upper == id }
            @ranks[id] = below.min - 1 if sinkable?(id, below)
          end
        end

        # Moving the node keeps every edge as long in total.
        def sinkable?(id, below)
          return false if below.empty? || below.min - 1 <= @ranks[id]

          @ends.count { |_, lower, _| lower == id } == below.size
        end

        def stacked(order)
          layers = Array.new((@ranks.values.max * 2) + 1) { [] }
          order.each { |id| layers[@ranks[id] * 2] << id }
          chain_order.each { |k| chain(k, layers) }
          layers
        end

        # dagre adds a turned edge back after all the others.
        def chain_order
          @ends.each_index.sort_by { |k| [@ends[k].last ? 1 : 0, k] }
        end

        def chain(k, layers)
          upper, lower, = @ends[k]
          crossed = ((@ranks[upper] * 2) + 1).upto((@ranks[lower] * 2) - 1)
          last = crossed.reduce(upper) do |above, layer|
            dummy = [:chain, k, layer]
            layers[layer] << dummy
            @dummies << dummy
            @links << [above, dummy]
            dummy
          end
          @links << [last, lower]
        end

        # One downward pass of dagre's barycenter ordering: a node goes
        # under the mean place of what links into it from above, and one
        # with nothing above keeps its place.
        def sweep(layers)
          above = Hash.new { |hash, key| hash[key] = [] }
          @links.each { |upper, lower| above[lower] << upper }
          layers.drop(1).each_with_object([layers.first]) do |layer, done|
            done << ordered(layer, above, done.last)
          end
        end

        def ordered(layer, above, previous)
          index = previous.each_with_index.to_h
          fixed, free = layer.each_with_index.partition do |id, _|
            above[id].empty?
          end
          sorted = free.sort_by do |id, place|
            [above[id].sum { |upper| index[upper] }.fdiv(above[id].size), place]
          end
          sorted = sorted.map(&:first)
          fixed.each { |id, place| sorted.insert([place, sorted.size].min, id) }
          sorted
        end
      end
    end
  end
end
