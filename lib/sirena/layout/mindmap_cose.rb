# frozen_string_literal: true

require_relative "mindmap_cose_body"
require_relative "mindmap_cose_link"
require_relative "mindmap_cose_seed"
require_relative "mindmap_cose_relaxation"

module Sirena
  module Layout
    # Force-directed placement of a mindmap tree, reproducing the
    # cose-bilkent layout mmdc runs: a radial seed followed by spring and
    # repulsion relaxation. The result depends on node order, so pass
    # nodes and links in the order mmdc does (depth-first).
    #
    # @example
    #   MindmapCose.call([["a", 60, 34], ["b", 80, 34]], [%w[a b]])
    #   # => { "a" => [x, y], "b" => [x, y] }
    class MindmapCose
      MARGIN = 15.0
      WORLD_CENTRE = [1200.0, 900.0].freeze

      # @param sizes [Array<Array>] [id, width, height] per node, root first
      # @param edges [Array<Array>] [parent id, child id] pairs
      # @return [Hash{String => Array<Float>}] box centre per id, with the
      #   top left of the margin-padded layout bounds at the origin
      def self.call(sizes, edges)
        new(sizes, edges).call
      end

      def initialize(sizes, edges)
        @bodies = sizes.map { |id, width, height| MindmapCoseBody.new(id, width, height) }
        @links = connect(edges)
      end

      def call
        return {} if @bodies.empty?

        width, height = MindmapCoseSeed.new(@bodies).place
        shift_to(WORLD_CENTRE[0] - (width / 2), WORLD_CENTRE[1] - (height / 2))
        MindmapCoseRelaxation.new(@bodies, @links).run
        shift_to(0.0, 0.0)
        @bodies.to_h { |body| [body.id, [body.center_x, body.center_y]] }
      end

      private

      def connect(edges)
        by_id = @bodies.to_h { |body| [body.id, body] }
        edges.filter_map do |source, target|
          first = by_id.fetch(source)
          second = by_id.fetch(target)
          next if first.equal?(second) || first.neighbors.include?(second)

          MindmapCoseLink.new(first, second).tap do |link|
            first.links << link
            second.links << link
          end
        end
      end

      def origin
        [@bodies.map(&:x).min, @bodies.map(&:y).min]
      end

      def shift_to(world_x, world_y)
        left, top = origin
        device_x = left - MARGIN
        device_y = top - MARGIN
        @bodies.each do |body|
          body.x = world_x + (body.x - device_x)
          body.y = world_y + (body.y - device_y)
        end
      end
    end
  end
end
