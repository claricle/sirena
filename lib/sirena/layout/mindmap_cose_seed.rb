# frozen_string_literal: true

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
        ring = [tree.map(&:diagonal).max, RING_GAP].max
        branch(centre, nil, 0.0, ANGLE_SPAN, 0.0, ring)
        move_to_origin
      end

      private

      attr_reader :bodies

      def breadth_first_order
        order = [bodies.first]
        order.each do |body|
          body.neighbors.each { |other| order << other unless order.include?(other) }
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
          body = remaining.delete_at(index)
          body.neighbors.each do |other|
            next if removed.include?(other)

            degrees[other] -= 1
            fresh << other if degrees[other] == 1
          end
          index += 1
        end
        removed.concat(fresh)
      end

      def move_to_origin
        left = bodies.map(&:x).min
        top = bodies.map(&:y).min
        width = bodies.map(&:right).max - left
        height = bodies.map(&:bottom).max - top
        bodies.each do |body|
          body.x -= left
          body.y -= top
        end
        [width, height]
      end

      def branch(body, parent, start_angle, end_angle, distance, ring)
        angle = (angle_midpoint(start_angle, end_angle) + start_angle).remainder(360)
        radians = (angle * (2.0 * Math::PI)) / 360
        body.center = [distance * Math.cos(radians),
                       distance * Math.sin(radians)]
        place_children(body, parent, start_angle, end_angle,
                       distance + ring, ring)
      end

      def angle_midpoint(start_angle, end_angle)
        half = ((end_angle - start_angle) + 1) / 2.0
        half.negative? ? half + 180 : half
      end

      def place_children(body, parent, start_angle, end_angle, distance, ring)
        links = body.links
        count = links.length - (parent ? 1 : 0)
        step = (end_angle - start_angle).abs / count.to_f
        index = parent ? (links.index { |link| link.other_end(body).equal?(parent) } + 1) % links.length : 0
        placed = 0
        while placed != count
          child = links[index].other_end(body)
          unless child.equal?(parent)
            first = (start_angle + (placed * step)).remainder(360)
            branch(child, body, first, (first + step).remainder(360), distance, ring)
            placed += 1
          end
          index = (index + 1) % links.length
        end
      end
    end
  end
end
