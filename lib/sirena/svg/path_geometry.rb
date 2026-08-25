# frozen_string_literal: true

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
    # exact tangent for a Bezier. An arc has no control point, and its chord
    # is not its tangent — on a half-circle the two are 90 degrees apart — so
    # an arc yields no heading at all rather than a head pointing the wrong
    # way. Sirena emits arcs only on rounded shapes and pie slices, never on
    # a path carrying a marker, so nothing it renders loses an arrowhead to
    # this; getting one there needs the arc's centre parameterisation.
    #
    # A command it cannot follow leaves the anchor nil, and the caller draws
    # nothing rather than drawing it in the wrong place.
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
        walk(data.to_s)
      end

      # @return [Anchor, nil] the first point, pointing along the first segment
      def origin
        # `false` means a command that anchors nothing came first, so the
        # segment after it must not be promoted to the start of the path.
        return nil unless @origin

        start, reference = @origin
        heading(start, start, reference)
      end

      # @return [Anchor, nil] the last point, pointing along the last segment
      def terminus
        return nil unless @terminus

        reference, finish = @terminus
        heading(finish, reference, finish)
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
        data.scan(TOKEN) do |command, number|
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
        return move(args) if lower == 'm'
        return close if lower == 'z'
        return traverse([args[5], args[6]]) if lower == 'a'

        segment(*references(lower, args))
      end

      # Moves the current point along a segment that offers no usable
      # tangent. The point has to advance or every command after it lands in
      # the wrong place, but neither end of an arc may anchor an arrowhead.
      #
      # An arc reached before any origin was settled closes the question
      # rather than leaving it open: the path starts on that arc, and the
      # segment after it is not the start of the path.
      def traverse(end_point)
        @origin = false if @origin.nil?
        @terminus = nil
        @point = end_point
      end

      # The segment a command draws, as [outgoing reference, incoming
      # reference, end point]. A straight segment is its own tangent, so both
      # references are the far end of it; a curve takes the control point
      # nearest each end.
      #
      # `s` and `t` carry a control point implied by the previous command
      # rather than one of their own, so they use the explicit control point
      # on both sides. Neither appears in Sirena's own output. An arc gives
      # no references at all — see the note on the class.
      def references(lower, args)
        case lower
        when 'l' then straight([args[0], args[1]])
        when 'h' then straight([args[0], @point[1]])
        when 'v' then straight([@point[0], args[0]])
        when 'c' then [[args[0], args[1]], [args[2], args[3]], [args[4], args[5]]]
        when 's', 'q' then [[args[0], args[1]], [args[0], args[1]], [args[2], args[3]]]
        when 't' then straight([args[0], args[1]])
        end
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
        @point = [args[0], args[1]]
        @subpath_start = @point
      end

      def close
        segment(@subpath_start, @point, @subpath_start)
      end

      def segment(out_reference, in_reference, end_point)
        @origin = [@point, out_reference] if @origin.nil?
        @terminus = [in_reference, end_point]
        @point = end_point
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
        length = Math.sqrt((dx * dx) + (dy * dy))
        # Not merely non-zero: path data carrying an out-of-range exponent
        # reaches here as Infinity, and Infinity/Infinity is NaN, which would
        # be written into the polygon's points verbatim.
        return nil unless length.finite? && length.positive?

        Anchor.new(at[0], at[1], dx / length, dy / length)
      end
    end
  end
end
