# frozen_string_literal: true

require_relative "grid"
require_relative "flowchart/directed_placement"

module Sirena
  module Layout
    # Places an ordinary connected pair in a vertical lane, three or more flat
    # classes in dagre-style ranks, and a lone class or a note pair in Grid's
    # three columns. Diagrams with namespaces keep Grid's own cells.
    class ClassCellPlacement
      CELL_GAP = 50
      # mmdc's dagre spaces class boxes 50 apart, not Grid's 80.
      DAGRE_GAP = 50

      # @param graph [Hash] the graph to position in place
      # @return [Hash] the same graph
      def self.apply(graph)
        children = graph[:children] || []
        return layered(graph) if layered?(children)

        pair = connected_pair(graph, children)
        if pair
          pack_connected_pair(*pair)
        elsif children.none? { |child| nested?(child) }
          pack(children)
        end
        Grid.apply(graph)
      end

      def self.layered?(children)
        children.size >= 3 && children.none? { |child| nested?(child) }
      end

      def self.layered(graph)
        graph[:layoutOptions] = (graph[:layoutOptions] || {}).merge(
          Base::ElkOptions::NODE_NODE_SPACING => DAGRE_GAP,
          Base::ElkOptions::LAYER_SPACING => DAGRE_GAP,
        )
        Flowchart::DirectedPlacement.apply(graph)
      end

      def self.connected_pair(graph, children)
        return unless connected_pair_candidate?(graph, children)

        edge = Array(graph[:edges]).first
        terminals = edge_terminals(edge)
        map_pair(children, terminals, inheritance?(edge)) if terminals
      end

      def self.inheritance?(edge)
        edge.dig(:metadata, :relationship_type) == "inheritance"
      end

      def self.connected_pair_candidate?(graph, children)
        graph.dig(:layoutOptions, "elk.direction") == "DOWN" &&
          ordinary_pair?(children) && Array(graph[:edges]).one?
      end

      # mmdc ranks a relation as written, first class on top. The builder
      # swaps `<|--` ends, so for inheritance the earlier-mentioned class is
      # the written first one; other pairs keep the edge direction.
      def self.map_pair(children, terminals, mention_order)
        children_by_id = children.to_h { |child| [child[:id], child] }
        return unless children_by_id.size == 2
        return unless terminals.all? { |id| children_by_id.key?(id) }
        return children if mention_order

        terminals.map { |id| children_by_id.fetch(id) }
      end

      def self.ordinary_pair?(children)
        children.size == 2 && children.none? do |child|
          nested?(child) || child.dig(:metadata, :note)
        end
      end

      def self.edge_terminals(edge)
        return unless edge

        sources = Array(edge[:sources]).uniq
        targets = Array(edge[:targets]).uniq
        return unless sources.one? && targets.one? && sources != targets

        sources + targets
      end

      def self.pack_connected_pair(source, target)
        width = [source[:width].to_f, target[:width].to_f].max
        place(source, centered_x(source, width), Grid::MARGIN)
        place(
          target, centered_x(target, width),
          target_y(source)
        )
      end

      def self.target_y(source)
        source[:y].to_f + source[:height].to_f + CELL_GAP
      end

      def self.centered_x(child, width)
        Grid::MARGIN + ((width - child[:width].to_f) / 2)
      end

      def self.nested?(child)
        child[:children] || child[:id].to_s.start_with?("namespace:")
      end

      def self.pack(children)
        rows = children.each_slice(Grid::COLUMNS).to_a
        xs = offsets(columns(rows), :width)
        ys = offsets(rows, :height)
        rows.each_with_index do |row, index|
          row.each_with_index { |child, col| place(child, xs[col], ys[index]) }
        end
      end

      def self.columns(rows)
        Array.new(Grid::COLUMNS) { |col| rows.filter_map { _1[col] } }
      end

      def self.place(child, x_coord, y_coord)
        child[:x] ||= x_coord
        child[:y] ||= y_coord
      end

      def self.offsets(groups, axis)
        groups.each_with_object([Grid::MARGIN]) do |boxes, starts|
          starts << (starts.last + cell(boxes, axis))
        end
      end

      def self.cell(boxes, axis)
        boxes.map { |box| box[axis].to_f }.max.to_f + CELL_GAP
      end

      private_class_method :layered?, :layered, :connected_pair,
                           :connected_pair_candidate?, :inheritance?, :map_pair,
                           :ordinary_pair?, :edge_terminals,
                           :pack_connected_pair, :target_y, :centered_x, :pack,
                           :columns, :place, :offsets, :cell, :nested?
    end
  end
end
