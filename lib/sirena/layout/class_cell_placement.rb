# frozen_string_literal: true

require_relative "grid"

module Sirena
  module Layout
    # Places class boxes in Grid's three columns, sizing each column and row
    # to its largest box plus a gap, so classes never overlap and sit as
    # close as mermaid spaces them. Diagrams with namespaces keep Grid's
    # own cells.
    class ClassCellPlacement
      CELL_GAP = 50

      # @param graph [Hash] the graph to position in place
      # @return [Hash] the same graph
      def self.apply(graph)
        children = graph[:children] || []
        pack(children) unless children.any? { |child| nested?(child) }
        Grid.apply(graph)
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

      private_class_method :pack, :columns, :place, :offsets, :cell, :nested?
    end
  end
end
