# frozen_string_literal: true

module Sirena
  module Renderer
    # Routes one architecture-beta edge around whatever else is in the
    # diagram, instead of drawing straight through it. Geometry only, no
    # SVG. Not an extension of EdgeRouter (don't unify them): EdgeRouter
    # trims two boxes with geometry-derived faces (flowchart); here faces
    # are user-declared (`a:R -- T:b`) with arbitrarily many obstacles.
    #
    # Coordinate-compressed grid + direction-aware Dijkstra: a straight
    # line when already clear, else the shortest bent path that
    # leaves/arrives on the declared faces without crossing an obstacle's
    # interior (source/target boxes exempt only at the anchor - see `route`).
    class ArchitectureEdgeRouter
      # Outer escape line, added only when the natural grid (built purely
      # from existing box edges) has no clear path at all.
      MARGIN = 20

      # Dijkstra cost added when a hop changes direction, so the search
      # prefers fewer bends over merely fewer hops.
      TURN_PENALTY = 5

      FACE_NORMAL = {
        "L" => { x: -1, y: 0 },
        "R" => { x: 1, y: 0 },
        "T" => { x: 0, y: -1 },
        "B" => { x: 0, y: 1 },
      }.freeze

      GRID_STEPS = [[1, 0], [-1, 0], [0, 1], [0, -1]].freeze

      # A binary min-heap keyed on cost, so search_grid's Dijkstra pops the
      # cheapest frontier entry in O(log n) instead of re-sorting the whole
      # frontier on every pop. Ruby's stdlib has no heap; this is the whole
      # of what the search needs from one - push and pop, nothing else.
      class MinHeap
        def initialize
          @entries = []
        end

        def empty?
          @entries.empty?
        end

        def push(cost, item)
          @entries << [cost, item]
          sift_up(@entries.length - 1)
        end

        # @return [Array(Numeric, Object)] the lowest-cost (cost, item) pair
        def pop
          top = @entries.first
          last = @entries.pop
          unless @entries.empty?
            @entries[0] = last
            sift_down(0)
          end
          top
        end

        private

        def sift_up(index)
          while index.positive?
            parent = (index - 1) / 2
            break if @entries[parent][0] <= @entries[index][0]

            swap_entries(parent, index)
            index = parent
          end
        end

        def sift_down(index)
          size = @entries.length
          loop do
            smallest = smallest_entry(index, size)
            break if smallest == index

            swap_entries(index, smallest)
            index = smallest
          end
        end

        def smallest_entry(index, size)
          left = (2 * index) + 1
          [index, left, left + 1].select { |entry| entry < size }
            .min_by { |entry| @entries[entry][0] }
        end

        def swap_entries(first, second)
          @entries[first], @entries[second] = @entries[second], @entries[first]
        end
      end
      private_constant :MinHeap

      # @param from [Hash] edge source: point {x:,y:} anchor on the declared
      #   face; box {x:,y:,width:,height:} - a clearance obstacle a path may
      #   only touch at point, never cross, even though it's never in
      #   +obstacles+; side "L"/"R"/"T"/"B" - which face point sits on
      # @param to [Hash] edge target, same shape as +from+
      # @param obstacles [Array<Hash>] every OTHER box to route around (the
      #   caller already excludes from/to and any ancestor-or-equal group)
      # @return [Array<Hash>] ordered {x:,y:} points, from[:point] first,
      #   to[:point] last. Length 2 means a straight line was clear.
      def route(from:, to:, obstacles:)
        clearance_obstacles = obstacles + [from[:box], to[:box]]
        if straight_clear?(from[:point], to[:point], clearance_obstacles)
          return [from[:point], to[:point]]
        end

        path = shortest_path(from, to, clearance_obstacles)
        return [from[:point], to[:point]] unless path

        collapse_collinear(path)
      end

      private

      def straight_clear?(from_point, to_point, clearance_obstacles)
        clearance_obstacles.none? do |box|
          segment_crosses_box?(box, from_point, to_point)
        end
      end

      # General segment-vs-box interior test (the segment need not be
      # axis-aligned - a declared-face-to-declared-face anchor pair rarely
      # is, e.g. an R face to a T face). Finds the sub-range of t in [0,1]
      # where the segment's x is strictly inside the box's x-span AND its y
      # is strictly inside the box's y-span; a border touch does not count
      # as crossing, matching EdgeRouter#crosses_face?'s semantics.
      def segment_crosses_box?(box, first_point, second_point)
        x_interval = horizontal_interval(box, first_point, second_point)
        return false unless x_interval

        y_interval = vertical_interval(box, first_point, second_point)
        return false unless y_interval

        lo = [x_interval[0], y_interval[0], 0.0].max
        hi = [x_interval[1], y_interval[1], 1.0].min
        lo < hi
      end

      def horizontal_interval(box, first_point, second_point)
        axis_interval(first_point[:x], second_point[:x], box[:x] || 0,
                      right_of(box))
      end

      def vertical_interval(box, first_point, second_point)
        axis_interval(first_point[:y], second_point[:y], box[:y] || 0,
                      bottom_of(box))
      end

      # The [t_lo, t_hi] sub-range of t (segment parametrized as
      # c1 + t*(c2-c1)) where the coordinate is strictly between near and
      # far. nil when no such t exists - including a segment that runs
      # exactly along that axis outside (near, far), or exactly along its
      # border, since a border touch is not "strictly between".
      def axis_interval(first_coordinate, second_coordinate, near, far)
        if first_coordinate == second_coordinate
          return infinite_interval if
            first_coordinate.between?(near, far) &&
              ![near, far].include?(first_coordinate)

          return nil
        end

        step = (second_coordinate - first_coordinate).to_f
        [(near - first_coordinate) / step,
         (far - first_coordinate) / step].sort
      end

      def infinite_interval
        [-Float::INFINITY, Float::INFINITY]
      end

      def right_of(box)
        (box[:x] || 0) + (box[:width] || 0)
      end

      def bottom_of(box)
        (box[:y] || 0) + (box[:height] || 0)
      end

      def shortest_path(from, to, clearance_obstacles)
        grid = build_grid(
          from[:point], to[:point], clearance_obstacles, margin: false
        )
        path = search_grid(grid, from, to, clearance_obstacles)
        return path if path

        widened = build_grid(
          from[:point], to[:point], clearance_obstacles, margin: true
        )
        search_grid(widened, from, to, clearance_obstacles)
      end

      # Critical coordinate lines: every obstacle's own edges, plus the two
      # anchor points. With margin: true, one extra line MARGIN beyond the
      # overall extent on each side, clamped to >= 0 so a route can never
      # need a negative coordinate.
      def build_grid(from_point, to_point, clearance_obstacles, margin:)
        xs = [from_point[:x], to_point[:x]]
        ys = [from_point[:y], to_point[:y]]
        add_obstacle_coordinates(xs, ys, clearance_obstacles)
        add_margin_coordinates(xs, ys) if margin
        { xs: xs.uniq.sort, ys: ys.uniq.sort }
      end

      def add_obstacle_coordinates(x_coordinates, y_coordinates, obstacles)
        obstacles.each do |box|
          x_coordinates << (box[:x] || 0) << right_of(box)
          y_coordinates << (box[:y] || 0) << bottom_of(box)
        end
      end

      def add_margin_coordinates(x_coordinates, y_coordinates)
        x_coordinates << [x_coordinates.min - MARGIN, 0].max
        x_coordinates << (x_coordinates.max + MARGIN)
        y_coordinates << [y_coordinates.min - MARGIN, 0].max
        y_coordinates << (y_coordinates.max + MARGIN)
      end

      # Direction-aware Dijkstra over the grid-line intersections. A hop
      # between grid-adjacent points is a valid graph edge iff the short
      # segment it draws is not segment_crosses_box? for any obstacle - the
      # same predicate straight_clear? uses, so grid-edge validity and the
      # straight-line shortcut share one exact test. The first hop out of
      # from[:point] is constrained to FACE_NORMAL[from[:side]]; the
      # accepted goal state requires the last hop into to[:point] to be
      # -FACE_NORMAL[to[:side]].
      def search_grid(grid, from, to, clearance_obstacles)
        xs = grid[:xs]
        ys = grid[:ys]
        start = grid_position(xs, ys, from[:point])
        goal = grid_position(xs, ys, to[:point])
        return nil if start == goal

        required_first = face_direction(from[:side])
        required_last = face_direction(to[:side]).map(&:-@)
        find_grid_path(grid, start, goal, [required_first, required_last],
                       clearance_obstacles)
      end

      def grid_position(x_coordinates, y_coordinates, point)
        [x_coordinates.index(point[:x]), y_coordinates.index(point[:y])]
      end

      def face_direction(side)
        FACE_NORMAL.fetch(side).values_at(:x, :y)
      end

      def find_grid_path(grid, start, goal, directions, clearance_obstacles)
        required_first, required_last = directions
        goal_state = [goal[0], goal[1], required_last]
        context = search_context(start, grid)
        until context[:frontier].empty?
          path = visit_grid_state(context, goal_state, required_first,
                                  clearance_obstacles)
          return path if path
        end
        nil
      end

      def search_context(start, grid)
        frontier = MinHeap.new
        frontier.push(0, [start[0], start[1], nil])
        {
          grid: grid, frontier: frontier, previous: {},
          distances: { [start[0], start[1], nil] => 0 }
        }
      end

      def visit_grid_state(context, goal_state, required_first,
                           clearance_obstacles)
        cost, state = context[:frontier].pop
        return if stale_state?(context, state, cost)

        path = reconstruct_goal(context, state, goal_state)
        return path if path

        expand_grid_state(context, state, cost, required_first,
                          clearance_obstacles)
        nil
      end

      def stale_state?(context, state, cost)
        cost > context[:distances].fetch(state, Float::INFINITY)
      end

      def reconstruct_goal(context, state, goal_state)
        return unless state == goal_state

        grid = context[:grid]
        reconstruct(context[:previous], state, grid[:xs], grid[:ys])
      end

      def expand_grid_state(context, state, cost, required_first,
                            clearance_obstacles)
        grid = context[:grid]
        moves = expand(state, grid, required_first, clearance_obstacles)
        moves.each { |move| relax_grid_move(move, cost, state, context) }
      end

      def relax_grid_move(move, cost, state, context)
        next_state, step_cost = move
        new_cost = cost + step_cost
        distances = context[:distances]
        return if new_cost >= distances.fetch(next_state, Float::INFINITY)

        distances[next_state] = new_cost
        context[:previous][next_state] = state
        context[:frontier].push(new_cost, next_state)
      end

      def expand(state, grid, required_first, clearance_obstacles)
        GRID_STEPS.filter_map do |step|
          grid_move(state, step, grid, required_first, clearance_obstacles)
        end
      end

      def grid_move(state, step, grid, required_first, clearance_obstacles)
        x_index, y_index, direction = state
        return if direction.nil? && step != required_first

        next_x, next_y = next_grid_position(x_index, y_index, step)
        return unless grid_position_valid?(next_x, next_y, grid)

        points = grid_segment(x_index, y_index, next_x, next_y, grid)
        return unless straight_clear?(*points, clearance_obstacles)

        [[next_x, next_y, step], grid_step_cost(direction, step)]
      end

      def next_grid_position(x_index, y_index, step)
        [x_index + step[0], y_index + step[1]]
      end

      def grid_position_valid?(x_index, y_index, grid)
        x_index.between?(0, grid[:xs].length - 1) &&
          y_index.between?(0, grid[:ys].length - 1)
      end

      def grid_segment(x_index, y_index, next_x, next_y, grid)
        [{ x: grid[:xs][x_index], y: grid[:ys][y_index] },
         { x: grid[:xs][next_x], y: grid[:ys][next_y] }]
      end

      def grid_step_cost(direction, next_direction)
        direction && direction != next_direction ? 1 + TURN_PENALTY : 1
      end

      def reconstruct(prev, state, x_coordinates, y_coordinates)
        path = [state]
        path << prev[path.last] while prev.key?(path.last)
        path.reverse.map do |x_index, y_index, _direction|
          { x: x_coordinates[x_index], y: y_coordinates[y_index] }
        end
      end

      # Drops points that don't represent an actual direction change, so
      # the returned path only contains real bends.
      def collapse_collinear(points)
        return points if points.length <= 2

        result = [points.first]
        points.each_cons(3) do |before, at, after|
          result << at if direction(before, at) != direction(at, after)
        end
        result << points.last
        result
      end

      def direction(from, to)
        [to[:x] <=> from[:x], to[:y] <=> from[:y]]
      end
    end
  end
end
