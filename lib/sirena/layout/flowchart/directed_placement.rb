# frozen_string_literal: true

require_relative "../elk_placement"
require_relative "layer_spacing"
require_relative "row_centering"

module Sirena
  module Layout
    class Flowchart < Base
      # Places a flowchart with elkrb, one container at a time.
      #
      # elkrb does not size a subgraph around what it holds, so each subgraph
      # is laid out on its own, boxed with its title and padding, and then
      # placed as a fixed-size box in the level above. An edge is laid out at
      # the innermost subgraph that holds both of its ends, between the boxes
      # directly inside it.
      #
      # elkrb only lays out downward: a sideways graph is laid out with its
      # boxes turned on their side and the result turned back, and a reversed
      # one is mirrored.
      class DirectedPlacement
        CLUSTER_PADDING = 20.0
        CLUSTER_SIDE = 8.0
        CLUSTER_VERTICAL = 25.0
        TRANSPOSED = [Base::DIRECTION_RIGHT, Base::DIRECTION_LEFT].freeze
        MIRRORED_X = [Base::DIRECTION_LEFT].freeze
        MIRRORED_Y = [Base::DIRECTION_UP].freeze

        # @param graph [Hash] the graph to position in place
        # @return [Hash] the same graph
        def self.apply(graph)
          new.apply(graph)
        end

        def apply(graph)
          @options = graph[:layoutOptions] || {}
          @direction = @options[Base::ElkOptions::DIRECTION]
          @graph = graph
          @level_edges = edges_by_level(graph)
          place_level(graph[:children] || [], nil)
          graph
        end

        private

        def cluster?(box)
          box.dig(:metadata, :cluster) == true
        end

        # Maps a container id (nil for the page) to the edges laid out there,
        # each as [edge, source box id, target box id].
        def edges_by_level(graph)
          paths = {}
          index_paths(graph[:children] || [], [], paths)
          levels = Hash.new { |hash, key| hash[key] = [] }
          (graph[:edges] || []).each do |edge|
            level = level_of(edge, paths)
            levels[level[0]] << [edge, level[1], level[2]] if level
          end
          levels
        end

        def index_paths(boxes, ancestors, paths)
          boxes.each do |box|
            paths[box[:id]] = [*ancestors, box[:id]]
            index_paths(box[:children] || [], paths[box[:id]], paths)
          end
        end

        def level_of(edge, paths)
          source = paths[edge[:sources]&.first]
          target = paths[edge[:targets]&.first]
          divergence(source, target) if source && target
        end

        # Where two box paths part: [container id, source box id, target box
        # id]. Nil when one box holds the other.
        def divergence(source, target)
          shared = common_prefix(source, target)
          return if shared == source.length || shared == target.length

          [shared.zero? ? nil : source[shared - 1], source[shared],
           target[shared]]
        end

        def common_prefix(source, target)
          source.zip(target).take_while { |a, b| a == b }.length
        end

        def place_level(boxes, container)
          boxes.each { |box| place_cluster(box) if cluster?(box) }
          return if boxes.empty?

          flat = flat_graph(boxes, @level_edges[container])
          place_flat(flat)
          boxes.zip(flat[:children]) do |box, placed|
            box.merge!(x: placed[:x], y: placed[:y])
          end
        end

        # Boxes go to elkrb under their position, because a model may repeat
        # an id and elkrb needs each box named apart.
        def flat_graph(boxes, level_edges)
          names = {}
          boxes.each_with_index do |box, index|
            names[box[:id]] ||= "box-#{index}"
          end
          { id: @graph[:id], children: flat_children(boxes),
            edges: flat_edges(level_edges, names), layoutOptions: @options }
        end

        def flat_children(boxes)
          boxes.each_with_index.map do |box, index|
            { id: "box-#{index}", width: box[:width], height: box[:height] }
          end
        end

        def flat_edges(level_edges, names)
          level_edges.each_with_index.filter_map do |(edge, from, to), index|
            next unless names[from] && names[to]

            { id: "edge-#{index}", sources: [names[from]],
              targets: [names[to]], labels: edge[:labels] || [] }
          end
        end

        def place_cluster(cluster)
          contents = cluster[:children] || []
          place_level(contents, cluster[:id])
          if contents.empty?
            cluster[:width] = titled_width(cluster)
            cluster[:height] = CLUSTER_VERTICAL * 2
            return
          end

          fit(cluster, contents)
        end

        # The contents sit CLUSTER_SIDE from the left and CLUSTER_VERTICAL
        # below the top; a title wider than them stretches the box and the
        # contents are centred in it.
        def fit(cluster, contents)
          inner = right_of(contents) - left_of(contents)
          cluster[:width] = boxed_width(cluster, inner)
          settle(contents, cluster[:width] - inner)
          cluster[:height] = bottom_of(contents) + CLUSTER_VERTICAL
        end

        def boxed_width(cluster, inner)
          [inner + (CLUSTER_SIDE * 2), titled_width(cluster)].max.ceil
        end

        def settle(contents, spare)
          shift(contents, (spare / 2.0) - left_of(contents),
                CLUSTER_VERTICAL - top_of(contents))
        end

        def left_of(boxes)
          boxes.map { |box| box[:x] }.min
        end

        def top_of(boxes)
          boxes.map { |box| box[:y] }.min
        end

        def right_of(boxes)
          boxes.map { |box| box[:x] + box[:width] }.max
        end

        def bottom_of(boxes)
          boxes.map { |box| box[:y] + box[:height] }.max
        end

        def shift(boxes, delta_x, delta_y)
          boxes.each do |box|
            box[:x] += delta_x
            box[:y] += delta_y
          end
        end

        def titled_width(cluster)
          label_size(cluster, :width) + (CLUSTER_PADDING * 2)
        end

        def label_size(cluster, axis)
          label = (cluster[:labels] || []).first
          label ? label[axis].to_i : 0
        end

        def place_flat(flat)
          transposed = TRANSPOSED.include?(@direction)
          transpose(flat) if transposed
          flat[:layoutOptions] = @options.merge(
            Base::ElkOptions::DIRECTION => ElkPlacement::DOWN,
          )
          ElkPlacement.apply(flat)
          RowCentering.apply(flat)
          LayerSpacing.apply(flat, label_axis: transposed ? :width : :height)
          transpose(flat) if transposed
          mirror(flat)
        end

        # Swaps the axes of every box. Before the layout it turns the boxes
        # on their side; after, it undoes that.
        def transpose(flat)
          flat[:children].each do |box|
            box[:x], box[:y] = box[:y], box[:x] if box[:x]
            box[:width], box[:height] = box[:height], box[:width]
          end
        end

        def mirror(flat)
          boxes = flat[:children]
          flip(boxes, :x, :width) if MIRRORED_X.include?(@direction)
          flip(boxes, :y, :height) if MIRRORED_Y.include?(@direction)
        end

        def flip(boxes, axis, size)
          extent = boxes.map { |box| box[axis] + box[size] }.max
          boxes.each { |box| box[axis] = extent - box[axis] - box[size] }
        end
      end
    end
  end
end
