# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Flattens an SVG path `d` into points in local space. Lines contribute
    # their end points; cubic, quadratic and arc segments are sampled
    # (STEPS per segment), so a curve's bbox is a close approximation, not
    # exact. Glued arc flags ("a1 1 0 01 2 3") are not supported.
    class PathPoints
      STEPS = 32
      # command letter => [argument count, handler]
      COMMANDS = {
        "m" => [2, :move_to],
        "l" => [2, :line_segment],
        "h" => [1, :horizontal_segment],
        "v" => [1, :vertical_segment],
        "c" => [6, :cubic_segment],
        "s" => [4, :smooth_cubic_segment],
        "q" => [4, :quad_segment],
        "t" => [2, :smooth_quad_segment],
        "a" => [7, :arc_segment],
        "z" => [0, :close_segment],
      }.freeze
      CURVES = %w[c s q t].freeze
      LETTER = /\A[a-zA-Z]\z/

      TOKEN = /[a-zA-Z]|#{Matrix::NUMBER}/

      def initialize(path_data)
        @tokens = path_data.to_s.scan(TOKEN)
        @points = []
        @x = @y = @sx = @sy = 0.0
        @ctrl = nil
      end

      def points
        command = nil
        until @tokens.empty?
          command = next_command(command)
          run(command, take_arguments(command))
          command = following(command)
        end
        @points
      end

      private

      def next_command(previous)
        return @tokens.shift if @tokens.first.match?(LETTER)
        raise ArgumentError, "path data starts without a command" unless previous

        repeatable!(previous)
      end

      # Closepath takes no arguments (SVG 2 path grammar), so a number after
      # it can never be consumed; refusing it keeps the loop finite.
      def repeatable!(command)
        return command unless command.casecmp?("z")

        raise ArgumentError, "numbers after #{command}: no command to repeat"
      end

      def take_arguments(command)
        arity, = COMMANDS.fetch(command.downcase) do
          raise ArgumentError, "unsupported path command: #{command}"
        end
        args = @tokens.shift(arity).map(&:to_f)
        return args if args.size >= arity

        raise ArgumentError, "short path arguments for #{command}"
      end

      # Extra coordinate pairs after a moveto are implicit linetos.
      def following(command)
        return command unless command.downcase == "m"

        command == "M" ? "L" : "l"
      end

      def run(command, args)
        kind = command.downcase
        origin = command == kind ? [@x, @y] : [0.0, 0.0]
        send(COMMANDS.fetch(kind).last, args, origin)
        @ctrl = nil unless CURVES.include?(kind)
      end

      def pairs(args, origin)
        args.each_slice(2).map do |px, py|
          [px + origin[0], py + origin[1]]
        end
      end

      def move_to(args, origin)
        target = pairs(args, origin).first
        @sx, @sy = target
        line_to(target)
      end

      def line_segment(args, origin)
        line_to(pairs(args, origin).first)
      end

      def horizontal_segment(args, origin)
        line_to([args[0] + origin[0], @y])
      end

      def vertical_segment(args, origin)
        line_to([@x, args[0] + origin[1]])
      end

      def cubic_segment(args, origin)
        curve(pairs(args, origin))
      end

      def smooth_cubic_segment(args, origin)
        curve([reflect, *pairs(args, origin)])
      end

      def quad_segment(args, origin)
        curve(pairs(args, origin))
      end

      def smooth_quad_segment(args, origin)
        curve([reflect, pairs(args, origin).first])
      end

      def close_segment(_args, _origin)
        @x = @sx
        @y = @sy
      end

      def line_to(point)
        @x, @y = point
        @points << point
      end

      def reflect
        return [@x, @y] unless @ctrl

        [(2 * @x) - @ctrl[0], (2 * @y) - @ctrl[1]]
      end

      # Samples a cubic (three control points) or quadratic (two) Bezier from
      # the current point to the last control point.
      def curve(controls)
        start = [@x, @y]
        sample { |fraction| bezier([start, *controls], fraction) }
        @ctrl = controls[-2]
        line_to(controls.last)
      end

      def sample
        (1...STEPS).each { |i| @points << yield(i.to_f / STEPS) }
      end

      def bezier(controls, fraction)
        while controls.size > 1
          controls = controls.each_cons(2).map do |from, to|
            lerp(from, to, fraction)
          end
        end
        controls.first
      end

      def lerp(from, to, fraction)
        from.zip(to).map do |start, finish|
          start + ((finish - start) * fraction)
        end
      end

      def arc_segment(args, origin)
        target = [args[5] + origin[0], args[6] + origin[1]]
        sample_arc(args, target) unless flat_arc?(args, target)
        line_to(target)
      end

      # A zero radius or a zero-length arc is a straight line (SVG F.6.2).
      def flat_arc?(args, target)
        args.first(2).any?(&:zero?) || target == [@x, @y]
      end

      def sample_arc(args, target)
        rotation, large, sweep = args[2, 3]
        arc = ArcPoints.new(start: [@x, @y], target: target,
                            radii: args.first(2).map(&:abs),
                            rotation: rotation,
                            flags: [large != 0, sweep != 0])
        sample { |fraction| arc.at(fraction) }
      end
    end
  end
end
