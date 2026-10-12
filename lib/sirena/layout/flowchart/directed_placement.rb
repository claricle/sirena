# frozen_string_literal: true

require_relative "../elk_placement"
require_relative "cluster_reach"
require_relative "component_packing"
require_relative "layer_spacing"
require_relative "level_edges"
require_relative "level_frame"
require_relative "minimum_rank_spacing"
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
        EXTERNAL_CLUSTER_SIDE = 35.0
        NESTED_CLUSTER_SIDE = 37.5
        CLUSTER_VERTICAL = 25.0
        INDEPENDENT_CLUSTER_PADDING = 37.5
        MIRRORED_X = [Base::DIRECTION_LEFT].freeze
        MIRRORED_Y = [Base::DIRECTION_UP].freeze

        # @param graph [Hash] the graph to position in place
        # @return [Hash] the same graph
        def self.apply(graph, center_edge_labels: false)
          new(center_edge_labels).apply(graph)
        end

        def initialize(center_edge_labels)
          @center_edge_labels = center_edge_labels
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
          boxes.each do |box|
            next unless cluster?(box)

            place_cluster(box, frame, top_level: container.nil?)
          end
          return if boxes.empty?

          level_edges = @level_edges.at(container)
          place_boxes(boxes, level_edges, frame, nested: !container.nil?)
          ClusterReach.apply(boxes, level_edges, sideways: frame.sideways?)
        end

        def place_boxes(boxes, level_edges, frame, nested:)
          flat = flat_graph(boxes, level_edges)
          clusters = cluster_names(boxes)
          leading = nested ? linked_component_clusters(boxes) : []
          place_flat(flat, frame, clusters, leading)
          boxes.zip(flat[:children]) do |box, placed|
            box.merge!(x: placed[:x], y: placed[:y])
          end
        end

        def cluster_names(boxes)
          boxes.each_index.filter_map do |index|
            "box-#{index}" if cluster?(boxes[index])
          end
        end

        def linked_component_clusters(boxes)
          boxes.each_index.filter_map do |index|
            "box-#{index}" if split_linked_cluster?(boxes[index])
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

        # dagre re-adds an edge that ends on a subgraph after the others,
        # so crossing reduction sees it last.
        def flat_edges(level_edges, names)
          dagre_edge_order(level_edges).filter_map do |(edge, from, to), index|
            next unless names[from] && names[to]

            { id: "edge-#{index}", sources: [names[from]],
              targets: [names[to]], labels: edge[:labels] || [],
              metadata: edge[:metadata] || {} }
          end
        end

        def dagre_edge_order(level_edges)
          level_edges.each_with_index.sort_by do |(edge, *), index|
            [subgraph_edge?(edge) ? 1 : 0, index]
          end
        end

        def subgraph_edge?(edge)
          [edge[:sources]&.first, edge[:targets]&.first].any? do |id|
            cluster_id?(id)
          end
        end

        def cluster_id?(id)
          @cluster_ids ||= collect_clusters(@graph[:children] || [])
          @cluster_ids.include?(id)
        end

        def collect_clusters(boxes)
          boxes.flat_map do |box|
            [*(box[:id] if cluster?(box)),
             *collect_clusters(box[:children] || [])]
          end
        end

        def place_cluster(cluster, frame, top_level:)
          contents = cluster[:children] || []
          place_level(contents, cluster[:id], inner_frame(cluster, frame))
          if contents.empty?
            cluster[:width] = titled_width(cluster)
            cluster[:height] = CLUSTER_VERTICAL * 2
            return
          end

          fit(cluster, contents, cluster_padding(cluster, contents, top_level))
        end

        def cluster_padding(cluster, contents, top_level)
          if split_linked_cluster?(cluster) && !top_level
            return [EXTERNAL_CLUSTER_SIDE, Base::DEFAULT_NODE_SPACING]
          end
          if @level_edges.external?(cluster[:id])
            return external_cluster_padding(top_level)
          end
          return [CLUSTER_SIDE, CLUSTER_VERTICAL] unless top_level

          top_level_independent_padding(contents)
        end

        def external_cluster_padding(top_level)
          side = top_level ? EXTERNAL_CLUSTER_SIDE : NESTED_CLUSTER_SIDE
          [side, CLUSTER_VERTICAL]
        end

        def top_level_independent_padding(contents)
          nested = contents.select { |box| cluster?(box) }
          return [INDEPENDENT_CLUSTER_PADDING] * 2 if nested.empty?
          if nested.any? { |box| split_linked_cluster?(box) }
            return [INDEPENDENT_CLUSTER_PADDING, EXTERNAL_CLUSTER_SIDE]
          end
          if nested.all? { |box| (box[:children] || []).one? }
            return [INDEPENDENT_CLUSTER_PADDING, CLUSTER_VERTICAL]
          end

          [CLUSTER_SIDE, CLUSTER_VERTICAL]
        end

        # Mermaid retains declaration order when a nested subgraph combines
        # multiple linked components (for example, repeated subgraph ids).
        # Isolated nodes are excluded: ordinary disconnected clusters keep
        # the established compact frame and component packing.
        def split_linked_cluster?(cluster)
          return false unless cluster?(cluster)

          children = cluster[:children] || []
          edges = @level_edges.at(cluster[:id])
          linked = edges.flat_map { |_, from, to| [from, to] }.compact.uniq
          ids = children.map { |child| child[:id] }
          return false unless ids.size >= 4 && (ids - linked).empty?

          connected_components(ids, edges).size > 1
        end

        def connected_components(ids, edges)
          links = ids.to_h { |id| [id, []] }
          edges.each do |_, from, to|
            next unless links.key?(from) && links.key?(to)

            links[from] << to
            links[to] << from
          end
          ids.each_with_object([]) do |id, components|
            next if components.flatten.include?(id)

            components << connected_ids(id, links)
          end
        end

        def connected_ids(first, links)
          found = []
          pending = [first]
          until pending.empty?
            id = pending.shift
            next if found.include?(id)

            found << id
            pending.concat(links.fetch(id))
          end
          found
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

        # Independent leaf clusters use the pinned reference padding. Nested
        # or externally crossed clusters keep the compact padding that lets
        # their parent level own placement. A wider title still stretches the
        # box, with its contents centred inside it.
        def fit(cluster, contents, padding)
          side, vertical = padding
          inner = right_of(contents) - left_of(contents)
          cluster[:width] = boxed_width(cluster, inner, side)
          settle(contents, cluster[:width] - inner, vertical)
          cluster[:height] = bottom_of(contents) + vertical
        end

        def boxed_width(cluster, inner, side)
          [inner + (side * 2), titled_width(cluster)].max.ceil
        end

        def settle(contents, spare, vertical)
          shift(contents, (spare / 2.0) - left_of(contents),
                vertical - top_of(contents))
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

        def place_flat(flat, frame, cluster_names, leading_clusters)
          transposed = frame.sideways?
          transpose(flat) if transposed
          children = flat[:children]
          order_leading_clusters(flat, leading_clusters)
          flat[:layoutOptions] = downward_options(frame)
          ElkPlacement.apply(flat)
          apply_label_geometry(flat, transposed)
          MinimumRankSpacing.apply(flat, frame.rank_spacing)
          ComponentPacking.apply(flat, cluster_names)
          align_leading_clusters(flat, leading_clusters, transposed)
          flat[:children] = children
          transpose(flat) if transposed
          mirror(flat, frame.direction)
        end

        def order_leading_clusters(flat, leading_clusters)
          return if leading_clusters.empty?

          ordinary, leading = flat[:children].partition do |box|
            !leading_clusters.include?(box[:id])
          end
          flat[:children] = ordinary + leading
        end

        def align_leading_clusters(flat, leading_clusters, transposed)
          return if leading_clusters.empty?

          ordinary, leading = flat[:children].partition do |box|
            !leading_clusters.include?(box[:id])
          end
          anchor = ordinary.last
          return unless anchor

          axis, size = transposed ? %i[y height] : %i[x width]
          centre = anchor[axis] + (anchor[size] / 2.0)
          leading.each { |box| box[axis] = centre - (box[size] / 2.0) }
        end

        def apply_label_geometry(flat, transposed)
          axis = transposed ? :width : :height
          label_axis = axis if @center_edge_labels
          RowCentering.apply(flat, label_axis: label_axis)
          LayerSpacing.apply(flat, label_axis: axis)
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
