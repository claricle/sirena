# frozen_string_literal: true

module Sirena
  module Renderer
    # Routes one architecture-beta edge around whatever else is in the
    # diagram, instead of drawing straight through it.
    #
    # This is geometry only, in the same spirit as EdgeRouter: it takes an
    # anchor point and declared face on each end, plus the boxes to avoid,
    # and gives back the ordered points a path should pass through. Nothing
    # here knows about SVG.
    #
    # Not an extension of EdgeRouter: EdgeRouter solves a different problem
    # (centre-to-centre trim between exactly two boxes, cluster-corner
    # rounding) for flowchart, where attachment faces are derived from
    # geometry, not declared. Architecture-beta's faces are user-declared
    # (`a:R -- T:b`) and the diagram can hold arbitrarily many boxes an edge
    # has to route around, which EdgeRouter's two-box design does not
    # attempt.
    #
    # Algorithm: coordinate-compressed grid + direction-aware shortest path.
    # The grid lines are every obstacle's own edges plus the two anchor
    # points; a straight line is used whenever it is already clear (the
    # common case); otherwise a direction-constrained search finds the
    # shortest bent path that leaves the source on its declared face and
    # arrives at the target on its declared face without crossing any
    # obstacle's interior - including the edge's own source/target boxes,
    # which are exempt only at the exact anchor point (see `route`).
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

            @entries[parent], @entries[index] = @entries[index], @entries[parent]
            index = parent
          end
        end

        def sift_down(index)
          size = @entries.length
          loop do
            smallest = index
            left = (2 * index) + 1
            right = (2 * index) + 2
            smallest = left if left < size && @entries[left][0] < @entries[smallest][0]
            smallest = right if right < size && @entries[right][0] < @entries[smallest][0]
            break if smallest == index

            @entries[index], @entries[smallest] = @entries[smallest], @entries[index]
            index = smallest
          end
        end
      end
      private_constant :MinHeap

      # @param from [Hash] the edge's source endpoint:
      #   point: {x:,y:} anchor on box's declared face
      #   box:   {x:,y:,width:,height:} the box the edge leaves - included
      #          as a clearance obstacle (a straight or bent path may only
      #          touch it at point, never cross its interior) even though
      #          it is never in +obstacles+
      #   side:  "L"/"R"/"T"/"B" - which face point sits on
      # @param to [Hash] the edge's target endpoint, same shape as +from+
      # @param obstacles [Array<Hash>] every OTHER box to route around. The
      #   caller has already excluded the edge's own from/to nodes and any
      #   group that is an ancestor of (or equal to) either endpoint's group.
      # @return [Array<Hash>] ordered {x:,y:} points, from[:point] first and
      #   to[:point] last. Length 2 means a straight line was clear.
      def route(from:, to:, obstacles:)
        clearance_obstacles = obstacles + [from[:box], to[:box]]
        return [from[:point], to[:point]] if straight_clear?(from[:point], to[:point], clearance_obstacles)

        path = shortest_path(from, to, clearance_obstacles)
        return [from[:point], to[:point]] unless path

        collapse_collinear(path)
      end

      private

      def straight_clear?(from_point, to_point, clearance_obstacles)
        clearance_obstacles.none? { |box| segment_crosses_box?(box, from_point, to_point) }
      end

      # General segment-vs-box interior test (the segment need not be
      # axis-aligned - a declared-face-to-declared-face anchor pair rarely
      # is, e.g. an R face to a T face). Finds the sub-range of t in [0,1]
      # where the segment's x is strictly inside the box's x-span AND its y
      # is strictly inside the box's y-span; a border touch does not count
      # as crossing, matching EdgeRouter#crosses_face?'s semantics.
      def segment_crosses_box?(box, p1, p2)
        tx = axis_interval(p1[:x], p2[:x], box[:x] || 0, right_of(box))
        return false unless tx

        ty = axis_interval(p1[:y], p2[:y], box[:y] || 0, bottom_of(box))
        return false unless ty

        lo = [tx[0], ty[0], 0.0].max
        hi = [tx[1], ty[1], 1.0].min
        lo < hi
      end

      # The [t_lo, t_hi] sub-range of t (segment parametrized as
      # c1 + t*(c2-c1)) where the coordinate is strictly between near and
      # far. nil when no such t exists - including a segment that runs
      # exactly along that axis outside (near, far), or exactly along its
      # border, since a border touch is not "strictly between".
      def axis_interval(c1, c2, near, far)
        if c1 == c2
          return c1 > near && c1 < far ? [-Float::INFINITY, Float::INFINITY] : nil
        end

        step = (c2 - c1).to_f
        edges = [(near - c1) / step, (far - c1) / step].sort
        edges
      end

      def right_of(box)
        (box[:x] || 0) + (box[:width] || 0)
      end

      def bottom_of(box)
        (box[:y] || 0) + (box[:height] || 0)
      end

      def shortest_path(from, to, clearance_obstacles)
        grid = build_grid(from[:point], to[:point], clearance_obstacles, margin: false)
        path = search_grid(grid, from, to, clearance_obstacles)
        return path if path

        widened = build_grid(from[:point], to[:point], clearance_obstacles, margin: true)
        search_grid(widened, from, to, clearance_obstacles)
      end

      # Critical coordinate lines: every obstacle's own edges, plus the two
      # anchor points. With margin: true, one extra line MARGIN beyond the
      # overall extent on each side, clamped to >= 0 so a route can never
      # need a negative coordinate.
      def build_grid(from_point, to_point, clearance_obstacles, margin:)
        xs = [from_point[:x], to_point[:x]]
        ys = [from_point[:y], to_point[:y]]

        clearance_obstacles.each do |box|
          xs << (box[:x] || 0) << right_of(box)
          ys << (box[:y] || 0) << bottom_of(box)
        end

        if margin
          xs << [xs.min - MARGIN, 0].max << xs.max + MARGIN
          ys << [ys.min - MARGIN, 0].max << ys.max + MARGIN
        end

        { xs: xs.uniq.sort, ys: ys.uniq.sort }
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
        start = [xs.index(from[:point][:x]), ys.index(from[:point][:y])]
        goal = [xs.index(to[:point][:x]), ys.index(to[:point][:y])]
        return nil if start == goal

        required_first = [FACE_NORMAL[from[:side]][:x], FACE_NORMAL[from[:side]][:y]]
        required_last = [-FACE_NORMAL[to[:side]][:x], -FACE_NORMAL[to[:side]][:y]]
        goal_state = [goal[0], goal[1], required_last]

        dist = { [start[0], start[1], nil] => 0 }
        prev = {}
        frontier = MinHeap.new
        frontier.push(0, [start[0], start[1], nil])

        until frontier.empty?
          cost, state = frontier.pop
          next if cost > dist.fetch(state, Float::INFINITY)
          return reconstruct(prev, state, xs, ys) if state == goal_state

          expand(state, xs, ys, required_first, clearance_obstacles).each do |next_state, step_cost|
            new_cost = cost + step_cost
            next if new_cost >= dist.fetch(next_state, Float::INFINITY)

            dist[next_state] = new_cost
            prev[next_state] = state
            frontier.push(new_cost, next_state)
          end
        end

        nil
      end

      def expand(state, xs, ys, required_first, clearance_obstacles)
        xi, yi, dir = state
        GRID_STEPS.filter_map do |dx, dy|
          next if dir.nil? && [dx, dy] != required_first

          nxi = xi + dx
          nyi = yi + dy
          next unless nxi.between?(0, xs.length - 1) && nyi.between?(0, ys.length - 1)

          p1 = { x: xs[xi], y: ys[yi] }
          p2 = { x: xs[nxi], y: ys[nyi] }
          next if clearance_obstacles.any? { |box| segment_crosses_box?(box, p1, p2) }

          new_dir = [dx, dy]
          turn_cost = dir && dir != new_dir ? TURN_PENALTY : 0
          [[nxi, nyi, new_dir], 1 + turn_cost]
        end
      end

      def reconstruct(prev, state, xs, ys)
        path = [state]
        path << prev[path.last] while prev.key?(path.last)
        path.reverse.map { |xi, yi, _dir| { x: xs[xi], y: ys[yi] } }
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
