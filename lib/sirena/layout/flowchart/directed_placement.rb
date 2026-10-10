# frozen_string_literal: true

require_relative "../elk_placement"

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
          return unless source && target

          shared = source.zip(target).take_while { |a, b| a == b }.length
          return if shared == source.length || shared == target.length

          [shared.zero? ? nil : source[shared - 1], source[shared],
           target[shared]]
        end

        def place_level(boxes, container)
          boxes.each { |box| place_cluster(box) if cluster?(box) }
          return if boxes.empty?

          flat = flat_graph(boxes, @level_edges[container])
          place_flat(flat)
          boxes.zip(flat[:children]) do |box, placed|
            box.merge!(x: placed[:x], y: placed[:y])
          end
          keep_sections(flat) if container.nil?
        end

        # Boxes go to elkrb under their position, because a model may repeat
        # an id and elkrb needs each box named apart.
        def flat_graph(boxes, level_edges)
          names = {}
          boxes.each_with_index { |box, index| names[box[:id]] ||= "box-#{index}" }
          {
            id: @graph[:id],
            children: boxes.each_with_index.map do |box, index|
              { id: "box-#{index}", width: box[:width], height: box[:height] }
            end,
            edges: flat_edges(level_edges, names),
            layoutOptions: @options,
          }
        end

        def flat_edges(level_edges, names)
          @routed = {}
          level_edges.each_with_index.filter_map do |(edge, from, to), index|
            next unless names[from] && names[to]

            @routed["edge-#{index}"] = edge if edge[:sources] == [from] &&
              edge[:targets] == [to]
            { id: "edge-#{index}", sources: [names[from]],
              targets: [names[to]], labels: edge[:labels] || [] }
          end
        end

        # An edge between two boxes of the page keeps the route elkrb found.
        def keep_sections(flat)
          flat[:edges].each do |placed|
            edge = @routed[placed[:id]]
            edge[:sections] = placed[:sections] if edge && placed[:sections]
          end
        end

        def place_cluster(cluster)
          contents = cluster[:children] || []
          place_level(contents, cluster[:id])
          band = title_band(cluster)
          if contents.empty?
            cluster[:width] = titled_width(cluster)
            cluster[:height] = band + CLUSTER_PADDING
            return
          end

          shift(contents, CLUSTER_PADDING - contents.map { |c| c[:x] }.min,
                band - contents.map { |c| c[:y] }.min)
          cluster[:width] = [contents.map { |c| c[:x] + c[:width] }.max +
                               CLUSTER_PADDING, titled_width(cluster)].max
          cluster[:height] =
            contents.map { |c| c[:y] + c[:height] }.max + CLUSTER_PADDING
        end

        def shift(boxes, delta_x, delta_y)
          boxes.each do |box|
            box[:x] += delta_x
            box[:y] += delta_y
          end
        end

        def title_band(cluster)
          label_size(cluster, :height) + (CLUSTER_PADDING * 2)
        end

        def titled_width(cluster)
          label_size(cluster, :width) + (CLUSTER_PADDING * 2)
        end

        def label_size(cluster, axis)
          label = (cluster[:labels] || []).first
          label ? label[axis].to_i : 0
        end

        def place_flat(flat)
          turned = TRANSPOSED.include?(@direction) ||
            MIRRORED_Y.include?(@direction)
          unless turned
            ElkPlacement.apply(flat)
            return
          end

          transpose(flat) if TRANSPOSED.include?(@direction)
          flat[:layoutOptions] = @options.merge(
            Base::ElkOptions::DIRECTION => ElkPlacement::DOWN,
          )
          ElkPlacement.apply(flat)
          transpose(flat) if TRANSPOSED.include?(@direction)
          mirror(flat)
        end

        # Swaps the axes of every box and every edge point. Before the layout
        # it turns the boxes on their side; after, it undoes that.
        def transpose(flat)
          flat[:children].each do |box|
            box[:x], box[:y] = box[:y], box[:x] if box[:x]
            box[:width], box[:height] = box[:height], box[:width]
          end
          each_point(flat) { |point| point[:x], point[:y] = point[:y], point[:x] }
        end

        def mirror(flat)
          horizontal = MIRRORED_X.include?(@direction)
          vertical = MIRRORED_Y.include?(@direction)
          return unless horizontal || vertical

          boxes = flat[:children]
          extent_x = boxes.map { |b| b[:x] + b[:width] }.max
          extent_y = boxes.map { |b| b[:y] + b[:height] }.max
          boxes.each do |box|
            box[:x] = extent_x - box[:x] - box[:width] if horizontal
            box[:y] = extent_y - box[:y] - box[:height] if vertical
          end
          each_point(flat) do |point|
            point[:x] = extent_x - point[:x] if horizontal
            point[:y] = extent_y - point[:y] if vertical
          end
        end

        def each_point(flat)
          (flat[:edges] || []).each do |edge|
            (edge[:sections] || []).each do |section|
              yield section[:startPoint]
              yield section[:endPoint]
              section[:bendPoints].each { |point| yield point }
            end
          end
        end
      end
    end
  end
end
