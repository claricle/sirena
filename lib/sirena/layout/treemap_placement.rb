# frozen_string_literal: true

require_relative "treemap_squarify"

module Sirena
  module Layout
    # Positions a treemap hierarchy like mmdc's d3 treemap: 10px between
    # siblings and around a section's content, plus a 25px header, then
    # rounds every edge to a whole pixel (JavaScript Math.round).
    class TreemapPlacement
      INNER = 10
      HEADER = 25

      def self.call(root, width, height)
        root.merge!(x0: 0.0, y0: 0.0, x1: width.to_f, y1: height.to_f)
        new.place(root, 0)
        round_all(root)
        root
      end

      def self.round_all(node)
        %i[x0 y0 x1 y1].each { |edge| node[edge] = (node[edge] + 0.5).floor }
        node[:children].each { |child| round_all(child) }
      end

      def place(node, inset)
        shrink(node, inset)
        return if node[:children].empty?

        TreemapSquarify.call(node[:children], node[:value], content(node))
        node[:children].each { |child| place(child, INNER / 2.0) }
      end

      private

      def content(node)
        half = INNER / 2.0
        [node[:x0] + half, node[:y0] + HEADER + half,
         node[:x1] - half, node[:y1] - half]
      end

      def shrink(node, inset)
        node[:x0], node[:x1] = collapse(node[:x0] + inset, node[:x1] - inset)
        node[:y0], node[:y1] = collapse(node[:y0] + inset, node[:y1] - inset)
      end

      def collapse(low, high)
        high < low ? [(low + high) / 2.0] * 2 : [low, high]
      end
    end
  end
end
