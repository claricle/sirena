# frozen_string_literal: true

require_relative "mindmap_cose_geometry"
require_relative "mindmap_cose_grid"

module Sirena
  module Layout
    # The spring-embedder loop of the mindmap force layout: edges pull their
    # boxes to an ideal length, nearby boxes push apart, and a cooling
    # schedule damps every move until the layout settles.
    class MindmapCoseRelaxation
      IDEAL_LENGTH = 50.0
      SPRING_STRENGTH = 0.45
      REPULSION_STRENGTH = 4500.0
      MIN_ITERATIONS = 2500
      CHECK_PERIOD = 100
      GRID_PERIOD = 10
      MAX_DISPLACEMENT = 300.0
      DISPLACEMENT_PER_BODY = 1.5
      MIN_REPULSION_DISTANCE = IDEAL_LENGTH / 10.0
      SEPARATION_BUFFER = IDEAL_LENGTH / 2.0
      REPULSION_RANGE = 2 * IDEAL_LENGTH
      FINAL_COOLING = CHECK_PERIOD.fdiv(MIN_ITERATIONS)
      COOLING_CYCLES = MIN_ITERATIONS / CHECK_PERIOD.to_f

      def initialize(bodies, links)
        @bodies = bodies
        @links = links
        @max_iterations = [bodies.length * 5, MIN_ITERATIONS].max
        @threshold = DISPLACEMENT_PER_BODY * bodies.length
        @grid = MindmapCoseGrid.new(bodies, REPULSION_RANGE)
        @cooling = 1.0
        @iterations = 0
        @cycle = 0
        @displacement = 0.0
        @previous_displacement = 0.0
      end

      def run
        nil until tick
      end

      private

      attr_reader :bodies, :links

      def tick
        @iterations += 1
        return true if @iterations == @max_iterations
        return true if (@iterations % CHECK_PERIOD).zero? && settled?

        @displacement = 0.0
        spring_forces
        repulsion_forces
        bodies.each { |body| @displacement += body.move(@cooling, MAX_DISPLACEMENT) }
        false
      end

      def settled?
        return true if converged?

        @cycle += 1
        decay = (@cycle**(Math.log(100 * (1.0 - FINAL_COOLING)) /
                          Math.log(COOLING_CYCLES))) / 100
        @cooling = [1.0 - decay, FINAL_COOLING].max
        false
      end

      def converged?
        oscillating = @iterations > @max_iterations / 3.0 &&
                      (@displacement - @previous_displacement).abs < 2
        converged = @displacement < @threshold
        @previous_displacement = @displacement
        converged || oscillating
      end

      def spring_forces
        links.each do |link|
          next unless link.measure && link.length != 0

          pull = SPRING_STRENGTH * (link.length - IDEAL_LENGTH)
          apply_spring(link, pull * (link.length_x / link.length),
                       pull * (link.length_y / link.length))
        end
      end

      def apply_spring(link, force_x, force_y)
        link.source.spring_x += force_x
        link.source.spring_y += force_y
        link.target.spring_x -= force_x
        link.target.spring_y -= force_y
      end

      def repulsion_forces
        @grid.refresh if (@iterations % GRID_PERIOD) == 1
        done = {}
        bodies.each do |body|
          @grid.refresh_surrounding(body, done) if (@iterations % GRID_PERIOD) == 1
          body.surrounding.each { |other| repel(body, other) }
          done[body] = true
        end
      end

      def repel(first, second)
        if MindmapCoseGeometry.intersects?(first, second)
          push_apart(first, second)
        else
          push_away(first, second)
        end
      end

      def push_apart(first, second)
        x, y = MindmapCoseGeometry.separation(first, second, SEPARATION_BUFFER)
        force_x = 2 * x
        force_y = 2 * y
        share = 1.0 / 2
        first.repulsion_x -= share * force_x
        first.repulsion_y -= share * force_y
        second.repulsion_x += share * force_x
        second.repulsion_y += share * force_y
      end

      def push_away(first, second)
        clip = MindmapCoseGeometry.clip_points(first, second)
        gap_x = minimum_gap(clip[2] - clip[0])
        gap_y = minimum_gap(clip[3] - clip[1])
        squared = (gap_x * gap_x) + (gap_y * gap_y)
        distance = Math.sqrt(squared)
        force = REPULSION_STRENGTH * 1.0 * 1.0 / squared
        force_x = force * gap_x / distance
        force_y = force * gap_y / distance
        first.repulsion_x -= force_x
        first.repulsion_y -= force_y
        second.repulsion_x += force_x
        second.repulsion_y += force_y
      end

      def minimum_gap(gap)
        return gap unless gap.abs < MIN_REPULSION_DISTANCE

        (gap <=> 0) * MIN_REPULSION_DISTANCE
      end
    end
  end
end
