# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Flattens an SVG path `d` into points in local space. Lines contribute
    # their end points; cubic, quadratic and arc segments are sampled
    # (STEPS per segment), so a curve's bbox is a close approximation, not exact.
    # Glued arc flags ("a1 1 0 01 2 3") are not supported.
    class PathPoints
      STEPS = 32
      ARITY = { "m" => 2, "l" => 2, "h" => 1, "v" => 1, "c" => 6, "s" => 4, "q" => 4, "t" => 2, "a" => 7, "z" => 0 }.freeze

      TOKEN = /[a-zA-Z]|#{Matrix::NUMBER}/

      def initialize(path_data)
        @tokens = path_data.to_s.scan(TOKEN)
        @points = []
        @x = @y = @sx = @sy = 0.0
        @ctrl = nil
      end

      def points
        cmd = nil
        until @tokens.empty?
          cmd = @tokens.shift if @tokens.first.match?(/\A[a-zA-Z]\z/)
          raise ArgumentError, "path data starts without a command" unless cmd

          arity = ARITY.fetch(cmd.downcase) { raise ArgumentError, "unsupported path command: #{cmd}" }
          args = @tokens.shift(arity).map(&:to_f)
          raise ArgumentError, "short path arguments for #{cmd}" if args.size < arity

          run(cmd, args)
          cmd = (cmd == "M" ? "L" : "l") if cmd.downcase == "m"
          break if arity.zero? && @tokens.empty?
        end
        @points
      end

      private

      def run(cmd, args)
        rel = cmd == cmd.downcase
        ox = rel ? @x : 0.0
        oy = rel ? @y : 0.0
        case cmd.downcase
        when "m" then move(args[0] + ox, args[1] + oy)
        when "l" then line_to(args[0] + ox, args[1] + oy)
        when "h" then line_to(args[0] + ox, @y)
        when "v" then line_to(@x, args[0] + oy)
        when "c" then cubic(args.each_slice(2).map { |px, py| [px + ox, py + oy] })
        when "s" then cubic([reflect(:cubic), *args.each_slice(2).map { |px, py| [px + ox, py + oy] }])
        when "q" then quad(args.each_slice(2).map { |px, py| [px + ox, py + oy] })
        when "t" then quad([reflect(:quad), [args[0] + ox, args[1] + oy]])
        when "a" then arc(args, ox, oy)
        when "z" then close
        end
        @ctrl = nil unless %w[c s q t].include?(cmd.downcase)
      end

      def move(x, y)
        @x = @sx = x
        @y = @sy = y
        @points << [x, y]
      end

      def line_to(x, y)
        @x = x
        @y = y
        @points << [x, y]
      end

      def close
        @x = @sx
        @y = @sy
      end

      def reflect(_kind)
        c = @ctrl
        c ? [(2 * @x) - c[0], (2 * @y) - c[1]] : [@x, @y]
      end

      def cubic(pts)
        p0 = [@x, @y]
        p1, p2, p3 = pts
        sample { |t| bezier([p0, p1, p2, p3], t) }
        @ctrl = p2
        line_to(*p3)
      end

      def quad(pts)
        p0 = [@x, @y]
        p1, p2 = pts
        sample { |t| bezier([p0, p1, p2], t) }
        @ctrl = p1
        line_to(*p2)
      end

      def sample
        (1...STEPS).each { |i| @points << yield(i.to_f / STEPS) }
      end

      def bezier(pts, t)
        pts = pts.each_cons(2).map { |(ax, ay), (bx, by)| [ax + ((bx - ax) * t), ay + ((by - ay) * t)] } while pts.size > 1
        pts.first
      end

      def arc(args, ox, oy)
        rx, ry, phi, large, sweep, ex, ey = args
        ex += ox
        ey += oy
        rx = rx.abs
        ry = ry.abs
        if rx.zero? || ry.zero? || (ex == @x && ey == @y)
          return line_to(ex, ey)
        end

        arc_points([rx, ry], phi * Math::PI / 180, large != 0, sweep != 0, ex, ey)
        line_to(ex, ey)
      end

      # SVG 1.1 appendix F.6.5: endpoint to center parameterization.
      def arc_points(radii, phi, large, sweep, ex, ey)
        rx, ry = radii
        cp = Math.cos(phi)
        sp = Math.sin(phi)
        dx = (@x - ex) / 2
        dy = (@y - ey) / 2
        x1 = (cp * dx) + (sp * dy)
        y1 = (-sp * dx) + (cp * dy)
        lam = ((x1**2) / (rx**2)) + ((y1**2) / (ry**2))
        if lam > 1
          rx *= Math.sqrt(lam)
          ry *= Math.sqrt(lam)
        end
        num = ((rx**2) * (ry**2)) - ((rx**2) * (y1**2)) - ((ry**2) * (x1**2))
        den = ((rx**2) * (y1**2)) + ((ry**2) * (x1**2))
        coef = Math.sqrt([num / den, 0].max) * (large == sweep ? -1 : 1)
        cx1 = coef * rx * y1 / ry
        cy1 = -coef * ry * x1 / rx
        cx = (cp * cx1) - (sp * cy1) + ((@x + ex) / 2)
        cy = (sp * cx1) + (cp * cy1) + ((@y + ey) / 2)
        th1 = Math.atan2((y1 - cy1) / ry, (x1 - cx1) / rx)
        th2 = Math.atan2((-y1 - cy1) / ry, (-x1 - cx1) / rx)
        dth = th2 - th1
        dth += 2 * Math::PI if sweep && dth.negative?
        dth -= 2 * Math::PI if !sweep && dth.positive?
        sample do |t|
          a = th1 + (dth * t)
          [cx + (cp * rx * Math.cos(a)) - (sp * ry * Math.sin(a)), cy + (sp * rx * Math.cos(a)) + (cp * ry * Math.sin(a))]
        end
      end
    end
  end
end
