# frozen_string_literal: true

module Sirena
  module Layout
    class Flowchart < Base
      # Sorts a graph's edges by where they are laid out: at the innermost
      # container that holds both ends, between the boxes directly inside it.
      class LevelEdges
        # @param graph [Hash] an ELK-shaped graph of nested boxes and edges
        def initialize(graph)
          @paths = {}
          index_paths(graph[:children] || [], [])
          @levels = Hash.new { |hash, key| hash[key] = [] }
          (graph[:edges] || []).each { |edge| file(edge) }
        end

        # @param container [String, nil] a container id, nil for the page
        # @return [Array] [edge, source box id, target box id] triples laid
        #   out at that container
        def at(container)
          @levels[container]
        end

        private

        def index_paths(boxes, ancestors)
          boxes.each do |box|
            @paths[box[:id]] = [*ancestors, box[:id]]
            index_paths(box[:children] || [], @paths[box[:id]])
          end
        end

        def file(edge)
          source = @paths[edge[:sources]&.first]
          target = @paths[edge[:targets]&.first]
          return unless source && target

          container, from, to = divergence(source, target)
          @levels[container] << [edge, from, to]
        end

        # Where two box paths part: [container id, source box id, target box
        # id]. When one box holds the other, one end is nil and flat_edges
        # drops the edge.
        def divergence(source, target)
          shared = common_prefix(source, target)
          [shared.zero? ? nil : source[shared - 1], source[shared],
           target[shared]]
        end

        def common_prefix(source, target)
          source.zip(target).take_while { |a, b| a == b }.length
        end
      end
    end
  end
end
