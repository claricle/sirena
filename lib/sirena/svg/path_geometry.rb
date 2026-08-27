# frozen_string_literal: true

require 'strscan'

module Sirena
  module Svg
    # Where a path starts and ends, and which way it is travelling there.
    #
    # Needed because SVG Tiny 1.2 has no markers, so an arrowhead has to be
    # drawn as its own shape at the right place and angle. Only the two ends
    # matter, so this walks the commands for the current point and never
    # builds the curves.
    #
    # Curve tangents are taken from the adjacent control point, which is the
    # exact tangent for a Bezier. A proper arc has no control point, and its
    # chord is not its tangent — on a half-circle the two are 90 degrees apart
    # — so it yields no heading rather than a head pointing the wrong way. A
    # zero-radius arc is the exception because SVG renders it as a straight
    # line. Sirena emits proper arcs only on rounded shapes and pie slices,
    # never on a path carrying a marker, so nothing it renders loses an
    # arrowhead to this; getting one there needs the arc's centre
    # parameterisation.
    #
    # An unrecognised byte is skipped, and any numbers after it are read as
    # more arguments for the command in force, which can move the anchor to a
    # point the path never reaches. This is deliberate leniency, like #flush
    # dropping a short argument group. It is reachable only through from_xml
    # on a foreign document because no Sirena renderer emits malformed path
    # data.
    class PathGeometry
      # One anchor: a point on the path and the unit direction of travel
      # through it.
      Anchor = Struct.new(:x, :y, :dx, :dy)

      # Command letter to the number of numbers it consumes. Repeated
      # argument groups are the SVG rule, so `L 1 2 3 4` is two segments.
      ARITY = {
        'm' => 2, 'l' => 2, 'h' => 1, 'v' => 1, 'c' => 6,
        's' => 4, 'q' => 4, 't' => 2, 'a' => 7, 'z' => 0
      }.freeze
      private_constant :ARITY

      TOKEN = /([MmLlHhVvCcSsQqTtAaZz])|([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)/
      private_constant :TOKEN

      # Arc flags are single digits even when no separator follows, so they
      # cannot use the generic number scan at their two argument positions.
      ARC_FLAG_TOKEN = /([MmLlHhVvCcSsQqTtAaZz])|([01])/
      private_constant :ARC_FLAG_TOKEN

      # A move followed by more coordinates draws lines: only the first
      # group of `M 1 2 3 4` is a move. Every other command simply repeats.
      AFTER_FIRST = { 'M' => 'L', 'm' => 'l' }.freeze
      private_constant :AFTER_FIRST

      # @param data [String, nil] the `d` attribute
      def initialize(data)
        @point = [0.0, 0.0]
        @subpath_start = @point
        @origin = nil
        @terminus = nil
        @origin_direction = nil
        @recent_direction = nil
        @quadratic_control = nil
        @cubic_control = nil
        walk(data.to_s)
      end

      # @return [Anchor, nil] the first point, pointing along the first segment
      def origin
        # `false` means a command that anchors nothing came first, so the
        # segment after it must not be promoted to the start of the path.
        return nil unless @origin

        start, reference = @origin
        heading(start, start, reference) ||
          (@origin_direction && heading(start, *@origin_direction))
      end

      # @return [Anchor, nil] the last point, pointing along the last segment
      def terminus
        return nil unless @terminus

        reference, finish = @terminus
        heading(finish, reference, finish) ||
          (@recent_direction && heading(finish, *@recent_direction))
      end

      private

      def walk(data)
        each_command(data) { |letter, args| apply(letter, args) }
      end

      # Yields one command letter and one full argument group at a time,
      # repeating the letter while arguments remain. A bare `M` with four
      # numbers draws a line after the move, which is the SVG rule and the
      # reason this cannot just split on letters.
      def each_command(data, &block)
        letter = nil
        numbers = []
        scanner = StringScanner.new(data)
        loop do
          token = arc_flag_position?(letter, numbers) ? ARC_FLAG_TOKEN : TOKEN
          break unless scanner.scan_until(token)

          command = scanner[1]
          number = scanner[2]
          if command
            flush(letter, numbers, &block)
            letter = command
            numbers = []
          else
            numbers << number.to_f
          end
        end
        flush(letter, numbers, &block)
      end

      def arc_flag_position?(letter, numbers)
        return false unless letter&.downcase == 'a'

        (numbers.length % ARITY.fetch('a')).between?(3, 4)
      end

      # A group with too few numbers is dropped, and the walk carries on with
      # the next command. An arrowhead placed off a half-read command would
      # be worse than none. A conformant renderer is stricter still — it
      # abandons the whole path from the first error — but Sirena never emits
      # malformed data, and reading the rest costs nothing.
      def flush(letter, numbers)
        return if letter.nil?

        size = ARITY.fetch(letter.downcase)
        return yield(letter, []) if size.zero?

        numbers.each_slice(size).with_index do |group, index|
          break if group.size < size

          yield(index.zero? ? letter : AFTER_FIRST.fetch(letter, letter), group)
        end
      end

      def apply(letter, args)
        lower = letter.downcase
        args = relative(letter, lower, args)
        clear_unrelated_control(lower)
        return move(args) if lower == 'm'
        return close if lower == 'z'
        return arc(args) if lower == 'a'

        segment(*references(lower, args))
      end

      # Smooth commands may only reflect a control from the same curve
      # family immediately before them; retaining either control through a
      # different command would bend a later shorthand curve unexpectedly.
      def clear_unrelated_control(lower)
        case lower
        when 'q', 't' then @cubic_control = nil
        when 'c', 's' then @quadratic_control = nil
        else
          @quadratic_control = nil
          @cubic_control = nil
        end
      end

      def arc(args)
        end_point = [args[5], args[6]]
        return segment(*straight(end_point)) if args[0].zero? || args[1].zero?

        traverse(end_point)
      end

      # Moves the current point along a segment that offers no usable
      # tangent. The point has to advance or every command after it lands in
      # the wrong place, but neither end of an arc may anchor an arrowhead.
      #
      # A break in continuity before a pending origin gains a usable direction
      # closes the question rather than letting a later segment supply that
      # direction. An arc always breaks it because the path starts on that
      # unanchorable segment. A later move breaks it only after a zero-length
      # segment has recorded an origin; moves alone leave the question open for
      # the first real segment.
      def traverse(end_point)
        @origin = false if @origin_direction.nil?
        @terminus = nil
        @recent_direction = nil
        @point = end_point
      end

      # The segment a command draws, as [outgoing reference, incoming
      # reference, end point]. A straight segment is its own tangent, so both
      # references are the far end of it; a curve takes the control point
      # nearest each end.
      #
      # Smooth curves reflect the preceding control in absolute space so
      # relative and absolute commands follow the same geometry. An arc gives
      # no references at all — see the note on the class.
      def references(lower, args)
        case lower
        when 'l' then straight([args[0], args[1]])
        when 'h' then straight([args[0], @point[1]])
        when 'v' then straight([@point[0], args[0]])
        when 'c'
          @cubic_control = [args[2], args[3]]
          [[args[0], args[1]], @cubic_control, [args[4], args[5]]]
        when 's'
          out_reference = reflection(@cubic_control)
          @cubic_control = [args[0], args[1]]
          [out_reference, @cubic_control, [args[2], args[3]]]
        when 'q'
          @quadratic_control = [args[0], args[1]]
          [@quadratic_control, @quadratic_control, [args[2], args[3]]]
        when 't'
          @quadratic_control = reflection(@quadratic_control)
          [@quadratic_control, @quadratic_control, [args[0], args[1]]]
        end
      end

      def reflection(control)
        source = control || @point
        [(@point[0] * 2) - source[0], (@point[1] * 2) - source[1]]
      end

      def straight(destination)
        [destination, @point, destination]
      end

      # Relative commands offset from the current point. On an arc only the
      # final coordinate pair is a point; the radii and flags are not.
      def relative(letter, lower, args)
        return args if letter == letter.upcase

        case lower
        when 'h' then [args[0] + @point[0]]
        when 'v' then [args[0] + @point[1]]
        when 'a' then args[0, 5] + [args[5] + @point[0], args[6] + @point[1]]
        else args.each_slice(2).flat_map { |x, y| [x + @point[0], y + @point[1]] }
        end
      end

      def move(args)
        @origin = false if @origin && @origin_direction.nil?
        @point = [args[0], args[1]]
        @subpath_start = @point
        @terminus = nil
        @recent_direction = nil
      end

      def close
        segment(@subpath_start, @point, @subpath_start)
      end

      def segment(out_reference, in_reference, end_point)
        @origin = [@point, out_reference] if @origin.nil?
        remember_directions(@point, out_reference, in_reference, end_point)
        @terminus = [in_reference, end_point]
        @point = end_point
      end

      # Degenerate endpoint derivatives still have a direction when another
      # edge of the same control polygon, or an earlier segment, establishes
      # one. Keeping the pair instead of an anchor lets the true endpoint be
      # supplied only when the caller asks for it. For a straight segment the
      # middle pair is reversed, but the first and third pairs are the same,
      # so the reversed one can never be `directions.first` or
      # `directions.last`.
      def remember_directions(*points)
        directions = points.each_cons(2).select do |from, to|
          heading(to, from, to)
        end
        return if directions.empty?

        @origin_direction ||= directions.first
        @recent_direction = directions.last
      end

      # Where the anchor sits is not where its direction comes from: the last
      # point heads AWAY from the control point behind it, while the first
      # heads TOWARDS the one in front. Both are the direction of travel, so
      # both are read from the same pair, and the point is passed separately
      # rather than assumed to be one end of it.
      #
      # @param at [Array] the point the anchor sits on
      # @param from [Array] the tail of the direction of travel
      # @param to [Array] the head of the direction of travel
      # @return [Anchor, nil] nil when the two coincide, which leaves no
      #   direction to point an arrowhead along
      def heading(at, from, to)
        dx = to[0] - from[0]
        dy = to[1] - from[1]
        length = Math.hypot(dx, dy)
        # Not merely non-zero: path data carrying an out-of-range exponent
        # can put Infinity in the anchor or in a coordinate delta. The guard
        # keeps Infinity/Infinity out of the heading and a non-finite anchor
        # out of the polygon's points.
        return nil unless at.all?(&:finite?) && length.finite? && length.positive?

        Anchor.new(at[0], at[1], dx / length, dy / length)
      end
    end
  end
end
