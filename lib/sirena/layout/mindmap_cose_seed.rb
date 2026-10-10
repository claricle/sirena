# frozen_string_literal: true

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

      # Peels leaves layer by layer; the survivor is the centre. The pass
      # removes every other node of the remaining list as it walks, so the
      # survivor depends on that order.
      def tree_centre(tree)
        remaining = tree.dup
        return remaining.first if remaining.length <= 2

        degrees = tree.to_h { |body| [body, body.neighbors.length] }
        removed = tree.select { |body| degrees[body] == 1 }
        peel(remaining, degrees, removed) until remaining.length <= 2
        remaining.first
      end

      def peel(remaining, degrees, removed)
        fresh = []
        index = 0
        while index < remaining.length
          fresh.concat(release(remaining.delete_at(index), degrees, removed))
          index += 1
        end
        removed.concat(fresh)
      end

      # @return [Array] the neighbours of body that just became leaves
      def release(body, degrees, removed)
        body.neighbors.filter_map do |other|
          next if removed.include?(other)

          degrees[other] -= 1
          other if degrees[other] == 1
        end
      end

      def move_to_origin
        left, top = top_left
        size = [bodies.map(&:right).max - left, bodies.map(&:bottom).max - top]
        bodies.each do |body|
          body.x -= left
          body.y -= top
        end
        size
      end

      def top_left
        [bodies.map(&:x).min, bodies.map(&:y).min]
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
        links = parent ? rotate_past(body.links, body, parent) : body.links
        others = links.map { |link| link.other_end(body) }
        others.reject { |other| other.equal?(parent) }
      end

      def rotate_past(links, body, parent)
        index = links.index { |link| link.other_end(body).equal?(parent) }
        links.rotate((index + 1) % links.length)
      end
    end
  end
end
