# frozen_string_literal: true

module Sirena
  module Renderer
    # Works out where an edge's line runs between two boxes.
    #
    # This is geometry only: it takes two laid-out boxes and gives back
    # the points the line passes through. Nothing here knows about SVG,
    # and FlowchartRenderer turns the points into a path.
    #
    # The maths exists because of clusters. A node is painted OVER the
    # line, so a line drawn from centre to centre looks right without
    # any trimming. A cluster is painted BEHIND the line, so the stretch
    # from its centre out to its border stays visible across the inside
    # of the box. Every rule below is about keeping that stretch off the
    # page while the line still touches the box it belongs to.
    #
    # One point shape throughout: `{ x: <number>, y: <number> }`, which
    # is the shape ELK bend points already have. `ends_of` is the single
    # place it becomes anything else.
    #
    # @example Route an edge
    #   points, label_ends = EdgeRouter.new.route(source, target, bends)
    class EdgeRouter
      # Rounded the way mermaid paints a cluster. The renderer draws the
      # same radius, and an endpoint on a corner has to land on it.
      CLUSTER_CORNER = 5

      # Two boxes that touch add up to exactly one run between their
      # centres, and the arithmetic lands a hair under it. Without the
      # slack they get trimmed to the same point and the edge is drawn
      # zero units long.
      TOUCHING = 1e-9

      # Routes are written to two decimal places after trimming. Centres
      # less than one output unit apart cannot provide a useful straight run.
      COINCIDENT = 0.01

      # Trimmed endpoints are written to two decimals, so a coordinate can
      # sit half a hundredth away from the unrounded side it reached.
      ROUTE_EPSILON = 0.01

      # How far a degenerate loop reaches past the borders it leaves.
      # The renderer's `calculate_width` and `calculate_height` add 40
      # past the drawn maxima, and `Base#create_document` keeps the
      # origin at zero and adds another 40 to the right and bottom
      # extents, leaving 80 units there. A reach beyond that needs the
      # page to grow with it.
      LOOP_REACH = 20

      # The marker Transform::FlowchartTransform puts on a subgraph.
      # Layout::Fallback#cluster? makes the same test: change one and
      # change the others, or the layers stop agreeing about what a box
      # is.
      #
      # @param box [Hash] a laid-out box
      # @return [Boolean] true when the box is a cluster
      def self.cluster?(box)
        box.dig(:metadata, :cluster) == true
      end

      # The exact centre of a laid-out box. The flowchart renderer aims
      # heads and outlines at this same point, so keep one copy: two drifted
      # apart once and put routed ends half a pixel off their heads.
      #
      # @param box [Hash] a laid-out box
      # @return [Hash] :x and :y of the centre
      def self.centre(box)
        { x: (box[:x] || 0) + ((box[:width] || 100) / 2.0),
          y: (box[:y] || 0) + ((box[:height] || 50) / 2.0) }
      end

      # The two ends of a run, flattened for the path and label builders.
      #
      # @param points [Array<Hash>] the points of a run
      # @return [Array<Numeric>] source x, source y, target x, target y
      def self.ends_of(points)
        first = points.first
        last = points.last
        [first[:x], first[:y], last[:x], last[:y]]
      end

      # Routes one edge.
      #
      # @param source [Hash] the laid-out box the edge leaves
      # @param target [Hash] the laid-out box the edge reaches
      # @param bends [Array<Hash>, nil] bend points the layout supplied
      # @return [Array(Array<Hash>, Array<Numeric>)] the points of the
      #   run, and the ends of the stretch the label sits on
      def route(source, target, bends = nil)
        points = nil
        unless exposed_cluster_overlap?(source, target)
          points = coincident_loop(source, target)
        end

        points ||= trimmed_route(source, target)
        source_neighbour = bends&.first || points[1]
        target_neighbour = bends&.last || points[-2]
        points[0] = clamp_cluster_corner(points[0], source_neighbour, source)
        points[-1] = clamp_cluster_corner(points[-1], target_neighbour, target)
        label_points = points.length > 2 ? points.slice(1, 2) : points

        [points, self.class.ends_of(label_points)]
      end

      private

      def cluster?(box)
        self.class.cluster?(box)
      end

      # Nodes and unmarked containers stay unchanged. A cluster is painted
      # with integer rectangle coordinates, so its endpoint is moved from the
      # layout box onto that exact rounded outline.
      def clamp_cluster_corner(point, neighbour, box)
        return point unless cluster?(box)

        x_side, y_side = cluster_sides(point, box)
        return point unless x_side || y_side

        outline = painted_cluster_outline(box)
        return point if outline.values_at(:rx, :ry).any?(&:zero?)
        return rounded_corner(neighbour, outline, x_side, y_side) if x_side && y_side

        clamp_cluster_side(point, outline, x_side, y_side)
      end

      def cluster_sides(point, box)
        [edge_side(point[:x], [box[:x] || 0, right_of(box)]),
         edge_side(point[:y], [box[:y] || 0, bottom_of(box)])]
      end

      def edge_side(coordinate, edges)
        side = edges.each_index.min_by { |index| (coordinate - edges[index]).abs }
        side if (coordinate - edges[side]).abs <= ROUTE_EPSILON
      end

      def painted_cluster_outline(box)
        x = (box[:x] || 0).to_i.to_f
        y = (box[:y] || 0).to_i.to_f
        width = (box[:width] || 0).to_i.to_f
        height = (box[:height] || 0).to_i.to_f
        xs = [x, x + width]
        ys = [y, y + height]
        { xs: xs, ys: ys,
          rx: [CLUSTER_CORNER, width / 2.0].min,
          ry: [CLUSTER_CORNER, height / 2.0].min }
      end

      def clamp_cluster_side(point, outline, x_side, y_side)
        xs, ys, rx, ry = outline.values_at(:xs, :ys, :rx, :ry)
        if x_side
          point.merge(x: xs[x_side], y: point[:y].clamp(ys.first + ry,
                                                        ys.last - ry))
        else
          point.merge(x: point[:x].clamp(xs.first + rx, xs.last - rx),
                      y: ys[y_side])
        end
      end

      def rounded_corner(neighbour, outline, x_side, y_side)
        xs, ys, rx, ry = outline.values_at(:xs, :ys, :rx, :ry)
        corner = { x: xs[x_side], y: ys[y_side] }
        centre = { x: x_side.zero? ? xs.first + rx : xs.last - rx,
                   y: y_side.zero? ? ys.first + ry : ys.last - ry }
        direction = { x: corner[:x] - neighbour[:x],
                      y: corner[:y] - neighbour[:y] }
        step = ellipse_entry(corner, centre, direction, rx, ry)
        return corner unless step

        corner.merge(x: (corner[:x] + (direction[:x] * step)).round(2),
                     y: (corner[:y] + (direction[:y] * step)).round(2))
      end

      def ellipse_entry(corner, centre, direction, rx, ry)
        x = (corner[:x] - centre[:x]) / rx
        y = (corner[:y] - centre[:y]) / ry
        dx = direction[:x] / rx
        dy = direction[:y] / ry
        a = (dx**2) + (dy**2)
        return nil if a.zero?

        b = 2 * ((x * dx) + (y * dy))
        smallest_quadratic_root(a, b)
      end

      def smallest_quadratic_root(a, b)
        discriminant = (b**2) - (4 * a)
        return nil if discriminant.negative?

        [(-b - Math.sqrt(discriminant)) / (2 * a),
         (-b + Math.sqrt(discriminant)) / (2 * a)]
          .select { |value| value >= 0 }.min
      end

      # A straight run needs a direction. Self-edges and distinct boxes
      # with the same centre have none, so route from the source's top to
      # the target's bottom with two bends beyond both boxes.
      def coincident_loop(source, target)
        source_centre = EdgeRouter.centre(source)
        target_centre = EdgeRouter.centre(target)
        return nil unless near?(source_centre, target_centre)

        source_top, = vertical_outline(source, source_centre[:y])
        _, target_bottom = vertical_outline(target, target_centre[:y])
        start = { x: source_centre[:x], y: source_top }
        finish = { x: target_centre[:x], y: target_bottom }
        out = [right_of(source), right_of(target)].max + LOOP_REACH
        bend_y = finish[:y]
        bend_y += LOOP_REACH if near?(start, finish)

        rounded_points([start, { x: out, y: start[:y] },
                        { x: out, y: bend_y }, finish])
      end

      def near?(first, second)
        Math.hypot(first[:x] - second[:x], first[:y] - second[:y]) < COINCIDENT
      end

      def right_of(box)
        (box[:x] || 0) + (box[:width] || 0)
      end

      def bottom_of(box)
        (box[:y] || 0) + (box[:height] || 0)
      end

      # Circle nodes use the smaller box dimension as their radius, so
      # their vertical outline may sit inside the box bounds.
      def vertical_outline(box, centre_y)
        y = box[:y] || 0
        height = box[:height] || 0
        shape = box.dig(:metadata, :shape)
        return [y, y + height] unless %w[circle double_circle].include?(shape)

        radius = [box[:width] || 0, height].min / 2
        [centre_y - radius, centre_y + radius]
      end

      # The points of the ordinary run: from centre to centre, with each
      # end pulled back to the border of the box it leaves when that box
      # is a cluster.
      def trimmed_route(source, target)
        from = EdgeRouter.centre(source)
        to = EdgeRouter.centre(target)
        out = step_out(source, from, to)
        back = step_out(target, to, from)

        # One centre can sit inside the other box even when neither box
        # contains the other. Detect that deep partial overlap from the
        # rectangles themselves before the centre-based nesting fallback.
        return exterior_route(source, target, from, to) if exposed_cluster_overlap?(source, target)

        # A step past the other centre means that centre is inside this
        # box. Use the opposite sides so the ordered route still points
        # from source to target while touching both borders.
        if out >= 1.0 - TOUCHING || back >= 1.0 - TOUCHING
          return enclosing_route(source, target, from, to)
        end

        # Partially overlapping or touching boxes need an exterior route:
        # their centre chord is visible through both cluster faces.
        return exterior_route(source, target, from, to) if out + back >= 1.0 - TOUCHING

        route = [along(from, to, out), along(to, from, back)]
        return exterior_route(source, target, from, to) if route.first == route.last

        route
      end

      def exposed_cluster_overlap?(source, target)
        return false unless cluster?(source) && cluster?(target)
        return false if contains_box?(source, target) || contains_box?(target, source)

        (source[:x] || 0) <= right_of(target) &&
          right_of(source) >= (target[:x] || 0) &&
          (source[:y] || 0) <= bottom_of(target) &&
          bottom_of(source) >= (target[:y] || 0)
      end

      def contains_box?(outer, inner)
        (outer[:x] || 0) <= (inner[:x] || 0) &&
          right_of(outer) >= right_of(inner) &&
          (outer[:y] || 0) <= (inner[:y] || 0) &&
          bottom_of(outer) >= bottom_of(inner)
      end

      def enclosing_route(source, target, from, to)
        source_back = step_out(source, from, mirror(from, to))
        target_back = step_out(target, to, mirror(to, from))

        [along(from, to, -source_back), along(to, from, -target_back)]
      end

      # The point as far the other side of `from` as `to` is this side.
      def mirror(from, to)
        { x: (2 * from[:x]) - to[:x], y: (2 * from[:y]) - to[:y] }
      end

      # Corners on the sides facing away from the other box expose both
      # ends. Prefer the corridor matching the centre direction, but unequal
      # projections can put that corner inside the other box, so only use a
      # candidate whose actual segments stay outside both open faces.
      def exterior_route(source, target, from, to)
        bottom = bottom_exterior_route(source, target, from, to)
        right = right_exterior_route(source, target, from, to)
        sideways = (to[:x] - from[:x]).abs >= (to[:y] - from[:y]).abs
        candidates = sideways ? [bottom, right] : [right, bottom]
        rounded = candidates.map { |points| rounded_points(points) }

        rounded.find { |route| clear_route?(route, source, target) } || rounded.first
      end

      def rounded_points(points)
        points.map do |point|
          { x: point[:x].round(2), y: point[:y].round(2) }
        end
      end

      def clear_route?(points, source, target)
        points.each_cons(2).none? do |from, to|
          [source, target].any? { |box| crosses_face?(box, from, to) }
        end
      end

      def crosses_face?(box, from, to)
        if from[:x] == to[:x]
          low, high = [from[:y], to[:y]].minmax
          from[:x] > (box[:x] || 0) && from[:x] < right_of(box) &&
            low < bottom_of(box) && high > (box[:y] || 0)
        else
          low, high = [from[:x], to[:x]].minmax
          from[:y] > (box[:y] || 0) && from[:y] < bottom_of(box) &&
            low < right_of(box) && high > (box[:x] || 0)
        end
      end

      def bottom_exterior_route(source, target, from, to)
        rightwards = to[:x] > from[:x]
        source_x = rightwards ? source[:x] || 0 : right_of(source)
        target_x = rightwards ? right_of(target) : target[:x] || 0
        source_y = bottom_of(source)
        target_y = bottom_of(target)
        outside_y = [source_y, target_y].max + LOOP_REACH

        [{ x: source_x, y: source_y }, { x: source_x, y: outside_y },
         { x: target_x, y: outside_y }, { x: target_x, y: target_y }]
      end

      def right_exterior_route(source, target, from, to)
        downwards = to[:y] > from[:y]
        source_x = right_of(source)
        target_x = right_of(target)
        source_y = downwards ? source[:y] || 0 : bottom_of(source)
        target_y = downwards ? bottom_of(target) : target[:y] || 0
        outside_x = [source_x, target_x].max + LOOP_REACH

        [{ x: source_x, y: source_y }, { x: outside_x, y: source_y },
         { x: outside_x, y: target_y }, { x: target_x, y: target_y }]
      end

      # How far along the ray to the other centre this box's border sits.
      # Values above one mean the other centre lies inside this box. A node
      # is not trimmed, so it stays where it is.
      #
      # Measured off the sides themselves rather than from half the
      # width: the centre above is the one this renderer has always
      # used, and its integer division puts it half a unit off centre on
      # an odd-width box. Halves either side of that would miss the side
      # by the same half unit.
      def step_out(box, from, to)
        return 0.0 unless cluster?(box)

        dx = to[:x] - from[:x]
        dy = to[:y] - from[:y]
        reach = []
        reach << side(from[:x], dx, box[:x] || 0, box[:width] || 0) unless dx.zero?
        reach << side(from[:y], dy, box[:y] || 0, box[:height] || 0) unless dy.zero?
        reach.empty? ? 0.0 : reach.min.clamp(0.0, Float::INFINITY)
      end

      # The side the run is heading for, as a fraction of the whole run.
      def side(from, delta, near, size)
        edge = delta.positive? ? near + size : near
        (edge - from) / delta.to_f
      end

      # An end that was not trimmed comes back exactly as it went in. A
      # box measured from text has a fractional centre, and touching
      # that moved every ordinary edge.
      #
      # A trimmed one is rounded, because the arithmetic lands on
      # seventeen digits behind the point and this output goes into a
      # document. Two decimals is finer than anything anyone draws.
      def along(from, to, step)
        return from if step.zero?

        { x: (from[:x] + ((to[:x] - from[:x]) * step)).round(2),
          y: (from[:y] + ((to[:y] - from[:y]) * step)).round(2) }
      end
    end
  end
end
