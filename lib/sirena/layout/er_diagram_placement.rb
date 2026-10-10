# frozen_string_literal: true

require_relative "er_diagram_entity_size"
require_relative "er_diagram_layering"
require_relative "er_diagram_ordering"
require_relative "er_diagram_coordinates"
require_relative "er_diagram_placement_node"

module Sirena
  module Layout
    # Positions entities top to bottom the way mmdc's dagre does: relations
    # point down the page, each rank is as tall as its tallest box, and a
    # labelled relation holds a label-sized gap between its two ranks.
    #
    # Same contract as Grid.apply: x and y are written into the graph Hash
    # in place, with the far corner of everything drawn under :extent.
    # Self-loops take no part in the placement.
    class ErDiagramPlacement
      NODE_SPACING = 140
      RANK_SPACING = 80
      EDGE_SPACING = 20
      MARGIN = 8
      LABEL_FONT_SIZE = 14
      LABEL_HEIGHT = 21

      # @param graph [Hash] the graph to position in place
      # @return [Hash] the same graph
      def self.apply(graph)
        new(graph).apply
      end

      def initialize(graph)
        @graph = graph
        @children = graph[:children] || []
        @edges = graph[:edges] || []
      end

      def apply
        return @graph if @children.empty?

        build_nodes
        layers = ErDiagramOrdering.call(@ranks, @chain)
        xs = ErDiagramCoordinates.call(
          layers, @chain, widths, dummies,
          node: NODE_SPACING, edge: EDGE_SPACING
        )
        write(layers, xs)
        @graph
      end

      private

      def build_nodes
        @nodes = @children.to_h do |child|
          [child[:id], entity_node(child)]
        end
        pairs = @edges.map do |edge|
          [edge[:sources]&.first, edge[:targets]&.first]
        end
        pairs = pairs.map { |pair| pair.all? { |id| @nodes.key?(id) } ? pair : [nil, nil] }
        @ranks, oriented = ErDiagramLayering.call(@nodes.keys, pairs)
        @chain = []
        oriented.each_with_index { |pair, index| add_chain(pair, index) }
      end

      # The relation becomes a chain of dummy nodes, one per rank crossed;
      # the middle one is as big as the label.
      def add_chain(pair, index)
        return unless pair

        from, to = pair
        low = @ranks[from]
        middle = low + ((@ranks[to] - low) / 2)
        previous = from
        ((low + 1)...@ranks[to]).each do |rank|
          dummy = dummy_node("#{index}:#{rank}", dummy_size(index, rank == middle))
          @nodes[dummy.id] = dummy
          @ranks[dummy.id] = rank
          @chain << [previous, dummy.id]
          previous = dummy.id
        end
        @chain << [previous, to]
      end

      def entity_node(child)
        ErDiagramPlacementNode.new(
          id: child[:id], width: child[:width], height: child[:height],
          dummy: false
        )
      end

      def dummy_node(id, size)
        ErDiagramPlacementNode.new(id: id, dummy: true, **size)
      end

      def dummy_size(index, middle)
        label = middle ? label_size(@edges[index]) : nil
        label || { width: 0, height: 0 }
      end

      def label_size(edge)
        text = (edge[:labels] || []).find { |item| !item[:position] }&.dig(:text)
        return if text.to_s.empty?

        { width: ErDiagramEntitySize.text_width(text) * LABEL_FONT_SIZE /
          ErDiagramEntitySize::FONT_SIZE, height: LABEL_HEIGHT }
      end

      def widths
        @nodes.transform_values(&:width)
      end

      def dummies
        @nodes.transform_values(&:dummy?)
      end

      # The canvas reaches as far as the widest label or edge route, not
      # only the entity boxes, so the extent covers every node in the layers.
      def write(layers, xs)
        left = layers.flatten.map { |id| xs[id] - (@nodes[id].width / 2.0) }.min
        top = MARGIN
        layers.each do |layer|
          tallest = layer.map { |id| @nodes[id].height }.max || 0
          layer.each do |id|
            next if @nodes[id].dummy?

            place(id, xs[id] - left + MARGIN, top + (tallest / 2.0))
          end
          top += tallest + (RANK_SPACING / 2.0)
        end
        @graph[:extent] = extent(layers, xs, left, top)
      end

      def extent(layers, xs, left, top)
        right = layers.flatten.map do |id|
          xs[id] - left + MARGIN + (@nodes[id].width / 2.0)
        end.max
        [right, top - (RANK_SPACING / 2.0)]
      end

      def place(id, center_x, center_y)
        child = @children.find { |item| item[:id] == id }
        child[:x] = center_x - (child[:width] / 2.0)
        child[:y] = center_y - (child[:height] / 2.0)
      end
    end
  end
end
