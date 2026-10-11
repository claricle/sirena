# frozen_string_literal: true

require_relative "grid"

module Sirena
  module Layout
    # Places an ordinary connected pair in a vertical lane and every other
    # flat class graph in Grid's three columns. Diagrams with namespaces keep
    # Grid's own cells.
    class ClassCellPlacement
      CELL_GAP = 50

      # @param graph [Hash] the graph to position in place
      # @return [Hash] the same graph
      def self.apply(graph)
        children = graph[:children] || []
        pair = connected_pair(graph, children)
        if pair
          pack_connected_pair(*pair)
        elsif children.none? { |child| nested?(child) }
          pack(children)
        end
        Grid.apply(graph)
      end

      def self.connected_pair(graph, children)
        return unless graph.dig(:layoutOptions, "elk.direction") == "DOWN"
        return unless ordinary_pair?(children)

        edge = Array(graph[:edges]).first if Array(graph[:edges]).one?
        terminals = edge_terminals(edge)
        child_ids = children.map { _1[:id] }
        return unless terminals && child_ids.uniq.size == 2
        return unless terminals.all? { |id| child_ids.include?(id) }

        children_by_id = children.to_h { |child| [child[:id], child] }
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
          source[:y].to_f + source[:height].to_f + CELL_GAP
        )
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

      private_class_method :connected_pair, :ordinary_pair?, :edge_terminals,
                           :pack_connected_pair, :centered_x, :pack, :columns,
                           :place, :offsets, :cell, :nested?
    end
  end
end
