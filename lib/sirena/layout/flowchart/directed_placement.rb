# frozen_string_literal: true

require_relative "../elk_placement"
require_relative "cluster_reach"
require_relative "layer_spacing"
require_relative "level_edges"
require_relative "level_frame"
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
        PAGE_MARGIN = 8.0
        CLUSTER_PADDING = 20.0
        CLUSTER_SIDE = 8.0
        CLUSTER_VERTICAL = 25.0
        MIRRORED_X = [Base::DIRECTION_LEFT].freeze
        MIRRORED_Y = [Base::DIRECTION_UP].freeze

        # @param graph [Hash] the graph to position in place
        # @return [Hash] the same graph
        def self.apply(graph)
          new.apply(graph)
        end

        def apply(graph)
          @options = graph[:layoutOptions] || {}
          @graph = graph
          @level_edges = LevelEdges.new(graph)
          place_level(graph[:children] || [], nil, root_frame)
          margin_page(graph[:children] || [])
          graph
        end

        private

        def root_frame
          LevelFrame.new(
            @options[Base::ElkOptions::DIRECTION],
            @options[Base::ElkOptions::LAYER_SPACING] ||
              Base::DEFAULT_LAYER_SPACING,
          )
        end

        # mmdc leaves PAGE_MARGIN round the diagram.
        def margin_page(boxes)
          return if boxes.empty?

          shift(boxes, PAGE_MARGIN - left_of(boxes),
                PAGE_MARGIN - top_of(boxes))
        end

        def cluster?(box)
          box.dig(:metadata, :cluster) == true
        end

        def place_level(boxes, container, frame)
          boxes.each { |box| place_cluster(box, frame) if cluster?(box) }
          return if boxes.empty?

          level_edges = @level_edges.at(container)
          flat = flat_graph(boxes, level_edges)
          place_flat(flat, frame)
          boxes.zip(flat[:children]) do |box, placed|
            box.merge!(x: placed[:x], y: placed[:y])
          end
          ClusterReach.apply(boxes, level_edges, sideways: frame.sideways?)
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

        def place_cluster(cluster, frame)
          contents = cluster[:children] || []
          place_level(contents, cluster[:id], inner_frame(cluster, frame))
          if contents.empty?
            cluster[:width] = titled_width(cluster)
            cluster[:height] = CLUSTER_VERTICAL * 2
            return
          end

          fit(cluster, contents)
        end

        # A subgraph with its own `direction`, or with no edge crossing its
        # border, is laid out as a graph of its own. Any other is laid out
        # with the level around it.
        def inner_frame(cluster, frame)
          direction = cluster.dig(:metadata, :direction)
          return frame.nested(direction) if direction
          return frame if @level_edges.external?(cluster[:id])

          frame.nested
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

        def place_flat(flat, frame)
          transposed = frame.sideways?
          transpose(flat) if transposed
          flat[:layoutOptions] = downward_options(frame)
          ElkPlacement.apply(flat)
          RowCentering.apply(flat)
          LayerSpacing.apply(flat, label_axis: transposed ? :width : :height)
          transpose(flat) if transposed
          mirror(flat, frame.direction)
        end

        def downward_options(frame)
          @options.merge(
            Base::ElkOptions::DIRECTION => ElkPlacement::DOWN,
            Base::ElkOptions::LAYER_SPACING => frame.rank_spacing,
          )
        end

        # Swaps the axes of every box. Before the layout it turns the boxes
        # on their side; after, it undoes that.
        def transpose(flat)
          flat[:children].each do |box|
            box[:x], box[:y] = box[:y], box[:x] if box[:x]
            box[:width], box[:height] = box[:height], box[:width]
          end
        end

        def mirror(flat, direction)
          boxes = flat[:children]
          flip(boxes, :x, :width) if MIRRORED_X.include?(direction)
          flip(boxes, :y, :height) if MIRRORED_Y.include?(direction)
        end

        def flip(boxes, axis, size)
          extent = boxes.map { |box| box[axis] + box[size] }.max
          boxes.each { |box| box[axis] = extent - box[axis] - box[size] }
        end
      end
    end
  end
end
