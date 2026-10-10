# frozen_string_literal: true

require_relative "mindmap_cose_geometry"
require_relative "mindmap_cose_trig"
require_relative "mindmap_cose_wedge"

module Sirena
  module Layout
    # Initial placement for a tree: the centre of the tree goes in the
    # middle and every branch gets an angular wedge, one ring per level.
    class MindmapCoseSeed
      RING_GAP = 50.0
      ANGLE_SPAN = 359.0

      def initialize(bodies)
        @bodies = bodies
      end

      # Positions every body with the top left of the tree at the origin.
      #
      # @return [Array<Float>] width and height of the placed tree
      def place
        tree = breadth_first_order
        centre = tree_centre(tree)
        @ring = [tree.map(&:diagonal).max, RING_GAP].max
        branch(centre, nil, MindmapCoseWedge.new(0.0, ANGLE_SPAN), 0.0)
        move_to_origin
      end

      private

      attr_reader :bodies

      def breadth_first_order
        order = [bodies.first]
        order.each do |body|
          body.neighbors.each do |other|
            order << other unless order.include?(other)
          end
        end
        order
      end

      # cose-base names the centre by peeling leaves layer by layer, but its
      # loop walks the whole node list instead of the leaves and drops every
      # other node on each pass. The survivor depends only on that order, so
      # the degree bookkeeping is left out.
      def tree_centre(tree)
        remaining = tree
        while remaining.length > 2
          remaining = remaining.select.with_index { |_, index| index.odd? }
        end
        remaining.first
      end

      def move_to_origin
        left, top, right, bottom = MindmapCoseGeometry.bounding_box(bodies)
        bodies.each do |body|
          body.x -= left
          body.y -= top
        end
        [right - left, bottom - top]
      end

      def branch(body, parent, wedge, distance)
        radians = (wedge.bearing * (2.0 * Math::PI)) / 360
        body.center = [distance * MindmapCoseTrig.cos(radians),
                       distance * MindmapCoseTrig.sin(radians)]
        place_children(body, parent, wedge, distance + @ring)
      end

      def place_children(body, parent, wedge, distance)
        children = children_in_order(body, parent)
        children.each_with_index do |child, index|
          branch(child, body, wedge.slice(index, children.length), distance)
        end
      end

      # The children start after the parent's link and wrap around.
      def children_in_order(body, parent)
        links = parent ? parent_first(body.links, body, parent) : body.links
        others = links.map { |link| link.other_end(body) }
        others.reject { |other| other.equal?(parent) }
      end

      # Rotates the parent's link to the front, so the others keep their
      # order after it.
      def parent_first(links, body, parent)
        links.rotate(links.index { |link| link.other_end(body).equal?(parent) })
      end
    end
  end
end
