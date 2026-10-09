# frozen_string_literal: true

require "nokogiri"

module SpecSupport
  module LayoutParity
    # Extracts the radius and sweep-angle analogs of SVG pie-sector paths.
    class PieSectorGeometry
      Measurement = Data.define(:radius, :sweep_angle)
      Comparison = Data.define(:radius_error, :sweep_error)
      Arc = Data.define(:start, :target, :radii, :rotation, :flags)

      COMMAND_ARITIES = { "m" => 2, "l" => 2, "a" => 7, "z" => 0 }.freeze
      LETTER = /\A[a-zA-Z]\z/
      EPSILON = 1e-9

      def self.extract(svg)
        document = Nokogiri::XML(svg) { |config| config.strict.nonet }
        document.remove_namespaces!
        paths = document.xpath("//path").select { |path| sector?(path) }
        paths.map { |path| new(path).measurement }
      end

      def self.compare(reference:, sirena:)
        Comparison.new(
          radius_error: analog_error(sirena.radius, reference.radius),
          sweep_error: analog_error(sirena.sweep_angle,
                                    reference.sweep_angle),
        )
      end

      def self.sector?(path)
        path["id"].to_s.start_with?("slice-") ||
          path["class"].to_s.split.include?("pieCircle")
      end
      private_class_method :sector?

      def self.analog_error(actual, reference)
        return 0.0 if actual.zero? && reference.zero?
        return Float::INFINITY if reference.zero?

        ((actual / reference) - 1).abs
      end
      private_class_method :analog_error

      def initialize(path)
        @path = path
        @vertices = []
        @arcs = []
        @current = @subpath_start = [0.0, 0.0]
      end

      def measurement
        parse_path
        arcs = @arcs.reject { |arc| degenerate_arc?(arc) }
        return Measurement.new(radius: 0.0, sweep_angle: 0.0) if arcs.empty?

        center = transform.apply(*center_point)
        samples = arcs.map { |arc| world_samples(arc) }
        Measurement.new(radius: radius(center, samples),
                        sweep_angle: sweep(center, samples))
      end

      private

      def parse_path
        PathPoints.new(@path["d"]).points
        @tokens = @path["d"].to_s.scan(PathPoints::TOKEN)
        command = nil
        until @tokens.empty?
          command = next_command(command)
          run(command, take_arguments(command))
          command = following(command)
        end
      end

      def next_command(previous)
        return @tokens.shift if @tokens.first.match?(LETTER)
        return previous if previous && !previous.casecmp?("z")

        raise ArgumentError, "pie path starts without a repeatable command"
      end

      def take_arguments(command)
        arity = COMMAND_ARITIES.fetch(command.downcase) do
          raise ArgumentError, "unsupported pie path command: #{command}"
        end
        args = @tokens.shift(arity).map(&:to_f)
        return args if args.size == arity

        raise ArgumentError, "short pie path arguments for #{command}"
      end

      def following(command)
        return command unless command.downcase == "m"

        command == "M" ? "L" : "l"
      end

      def run(command, args)
        case command.downcase
        when "m" then move(command, args)
        when "l" then line(command, args)
        when "a" then arc(command, args)
        when "z" then @current = @subpath_start
        end
      end

      def move(command, args)
        @current = point(command, args)
        @subpath_start = @current
        @vertices << @current
      end

      def line(command, args)
        @current = point(command, args)
        @vertices << @current
      end

      def arc(command, args)
        target = point(command, args.last(2))
        @arcs << Arc.new(start: @current, target: target,
                         radii: args.first(2).map(&:abs), rotation: args[2],
                         flags: [!args[3].zero?, !args[4].zero?])
        @current = target
      end

      def point(command, coordinates)
        return coordinates if command == command.upcase

        coordinates.zip(@current).map { |value, origin| value + origin }
      end

      def degenerate_arc?(arc)
        arc.radii.any?(&:zero?) || arc.start == arc.target
      end

      def center_point
        endpoints = @arcs.flat_map { |arc| [arc.start, arc.target] }
        centers = @vertices.reject do |vertex|
          endpoints.any? { |endpoint| same_point?(vertex, endpoint) }
        end.uniq
        return centers.first if centers.one?
        return [0.0, 0.0] if centers.empty?

        raise ArgumentError, "pie sector path has more than one center"
      end

      def same_point?(left, right)
        left.zip(right).all? { |a, b| (a - b).abs <= EPSILON }
      end

      def transform
        ancestors = @path.ancestors.reverse
        @transform ||= ancestors.reduce(Matrix.identity) do |ctm, node|
          ctm * Matrix.parse(node["transform"])
        end * Matrix.parse(@path["transform"])
      end

      def world_samples(arc)
        local = ArcPoints.new(start: arc.start, target: arc.target,
                              radii: arc.radii, rotation: arc.rotation,
                              flags: arc.flags)
        (0..PathPoints::STEPS).map do |index|
          transform.apply(*local.at(index.to_f / PathPoints::STEPS))
        end
      end

      def radius(center, samples)
        endpoints = samples.flat_map { |points| [points.first, points.last] }
        endpoints.sum { |point| distance(center, point) } / endpoints.size
      end

      def sweep(center, samples)
        samples.sum do |points|
          points.each_cons(2).sum do |from, to|
            signed_angle(vector(center, from), vector(center, to))
          end.abs
        end
      end

      def vector(origin, point)
        [point[0] - origin[0], point[1] - origin[1]]
      end

      def signed_angle(left, right)
        Math.atan2(cross_product(left, right), dot_product(left, right))
      end

      def cross_product(left, right)
        (left[0] * right[1]) - (left[1] * right[0])
      end

      def dot_product(left, right)
        (left[0] * right[0]) + (left[1] * right[1])
      end

      def distance(left, right)
        Math.hypot(right[0] - left[0], right[1] - left[1])
      end
    end
  end
end
