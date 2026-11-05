# frozen_string_literal: true

require_relative "../drawing"

module Sirena
  module Notation
    module PlantUML
      module Timing
        # Draws one participant's signal inside its track, and says where on
        # the track the signal is at a time (where a message arrow lands).
        class Signals
          GREEN = "#006400"
          LAVENDER = "#E2E2F0"
          # PlantUML draws a lane's names and its analog line in this grey.
          INK = "#333333"
          # Measured against the JAR: a lane's vertical rhythm.
          ROW = 20.0
          HIGH = 25.49
          LOW = 39.49
          BOTTOM = 18.0
          TIP = 12.0
          HEIGHTS = { "clock" => 47.49, "binary" => 47.49, "concise" => 56.49,
                      "analog" => 117.49 }.freeze
          # Where a lane's names sit, left of the plot (JAR measures).
          LABEL_X = 25.0
          LEAD = { "clock" => 30.0, "binary" => 30.0, "concise" => 25.0,
                   "robust" => 25.0, "analog" => 30.0 }.freeze
          NAME_DROP = 5.54
          SEGMENT_MIDDLE = 34.49
          CONCISE_RISE = 12.0
          ANALOG_LOW = 109.49
          MAX_EDGES = 2000
          private_constant :GREEN, :LAVENDER, :ROW, :HIGH, :LOW, :BOTTOM,
                           :TIP, :HEIGHTS, :MAX_EDGES, :INK, :LABEL_X, :LEAD,
                           :NAME_DROP, :SEGMENT_MIDDLE, :ANALOG_LOW,
                           :CONCISE_RISE

          # @param pen [Drawing::Pen]
          # @param diagram [Diagram]
          # @param axis [Axis]
          # @param left [Float] x where the plot starts
          def initialize(pen, diagram, axis, left)
            @pen = pen
            @diagram = diagram
            @axis = axis
            @left = left
          end

          # @return [Float] the track's height
          def height(participant)
            return HEIGHTS.fetch(participant.kind) unless
              participant.kind == "robust"

            HIGH + (ROW * [states(participant).size, 1].max)
          end

          # @return [Float] the least x the plot may start at for this lane:
          #   robust state names and analog bounds stand to its left
          def lead(participant)
            LEAD.fetch(participant.kind) + stand(participant)
          end

          # Writes the lane's names and bounds in the margin left of the plot.
          def draw_labels(participant, top)
            labels(participant, top).each do |name, y|
              if participant.kind == "robust"
                @pen.text(name, LABEL_X, Drawing::Face.middle(y + NAME_DROP,
                                                              12), fill: INK)
              else
                @pen.text(name, @left - 2, y, size: 14, bold: true,
                                              anchor: "end", fill: INK)
              end
            end
          end

          def draw(participant, top)
            send(:"draw_#{participant.kind}", participant, top)
          end

          # @return [Float] y of the signal at a time, or the track's middle
          def y_at(participant, top, time)
            return concise_y(participant, top, time) if
              participant.kind == "concise"
            return top + (height(participant) / 2) unless
              %w[binary robust].include?(participant.kind)

            level_y(participant, top, state_at(participant, time))
          end

          private

          # A concise lane's segment is a hexagon: a message that meets it
          # where a state changes meets its point, in the middle of the
          # lane; one that meets it between changes meets its top edge.
          def concise_y(participant, top, time)
            middle = top + SEGMENT_MIDDLE
            times = changes(participant).map(&:time)
            return middle if times.empty? || time <= times.first ||
              times.include?(time)

            middle - CONCISE_RISE
          end

          # How wide the lane's names stand left of its plot.
          def stand(participant)
            size, bold = participant.kind == "analog" ? [14, true] : [12, false]
            names = labels(participant, 0).map(&:first)
            return 0.0 unless %w[robust analog].include?(participant.kind)

            names.map { |n| Drawing::Face.width(n, size: size, bold: bold) }
              .max.to_f
          end

          def labels(participant, top)
            case participant.kind
            when "robust" then robust_labels(participant, top)
            when "analog" then analog_labels(participant, top)
            else []
            end
          end

          def robust_labels(participant, top)
            states(participant).map do |state|
              [state, level_y(participant, top, state)]
            end
          end

          def analog_labels(participant, top)
            low, high = values(participant).minmax
            [[high.to_s, Drawing::Face.middle(top + 30.78, 14)],
             [low.to_s, Drawing::Face.middle(top + 114.78, 14)]]
          end

          def changes(participant)
            @diagram.changes.select { |c| c.id == participant.id }
              .sort_by.with_index { |c, index| [c.time, index] }
          end

          def states(participant)
            changes(participant).map(&:state).uniq
          end

          def values(participant)
            list = changes(participant).map { |c| c.state.to_f }
            list.empty? ? [0.0] : list
          end

          def state_at(participant, time)
            current = changes(participant).select { |c| c.time <= time }.last
            current&.state
          end

          def level_y(participant, top, state)
            if participant.kind == "binary"
              return binary_high?(state) ? top + HIGH : top + LOW
            end

            index = states(participant).index(state) || 0
            top + height(participant) - BOTTOM - (index * ROW)
          end

          def binary_high?(state)
            %w[high 1 true].include?(state.to_s.downcase)
          end

          def draw_binary(participant, top)
            points = changes(participant).map do |c|
              [c.time, level_y(participant, top, c.state)]
            end
            points.unshift([@axis.start, level_y(participant, top, nil)]) if
              points.empty? || points.first.first > @axis.start
            steps(points, "2")
          end

          def draw_robust(participant, top)
            points = changes(participant).map do |c|
              [c.time, level_y(participant, top, c.state)]
            end
            steps(points, "2")
          end

          def draw_clock(participant, top)
            high = top + HIGH
            low = top + LOW
            level = ->(on) { on ? high : low }
            steps(clock_edges(participant).map { |t, on| [t, level.call(on)] })
          end

          def clock_edges(participant)
            start = @axis.start
            edges = edges_of(participant)
            inside = edges.select do |time, _on|
              time > start && time <= @axis.finish
            end
            opening(participant, edges, start) + inside
          end

          # An edge exactly at the start is drawn as a stroke up from the
          # opposite level, as PlantUML draws it.
          def opening(participant, edges, start)
            level = high_at?(participant, start)
            return [[start, level]] if edges.none? { |time, _| time == start }

            [[start, !level], [start, level]]
          end

          def high_at?(clock, time)
            return false if time < clock.offset

            ((time - clock.offset) % clock.period) < clock.pulse
          end

          def first_cycle(clock)
            [((@axis.start - clock.offset) / clock.period).floor, 0].max
          end

          def edges_of(clock)
            rises_of(clock).flat_map do |rise|
              [[rise, true], [rise + clock.pulse, false]]
            end
          end

          def rises_of(clock)
            first = first_cycle(clock)
            rises = (first...(first + MAX_EDGES)).map do |cycle|
              clock.offset + (cycle * clock.period)
            end
            rises.take_while { |rise| rise <= @axis.finish }
          end

          def steps(points, width = "1.5")
            return if points.empty?

            @pen.path(step_commands(points) +
                      [[:line, @axis.x(@axis.finish), points.last[1]]],
                      stroke: GREEN, stroke_width: width)
          end

          def step_commands(points)
            commands = [[:move, @axis.x(points.first[0]), points.first[1]]]
            points.each_cons(2) do |(_, from), (time, to)|
              commands << [:line, @axis.x(time), from]
              commands << [:line, @axis.x(time), to]
            end
            commands
          end

          def draw_concise(participant, top)
            list = changes(participant)
            list.each_with_index do |change, index|
              follower = list[index + 1]
              segment(change, follower&.time || @axis.finish, top, follower)
            end
          end

          def segment(change, finish, top, closed)
            left = @axis.x(change.time)
            right = @axis.x(finish)
            @pen.path(hexagon(left, right, top, closed),
                      fill: change.fill || LAVENDER,
                      stroke: change.stroke || GREEN, stroke_width: "1.5")
            label(change, left, right, top, closed)
          end

          # A name sits centred in a closed segment and flush after the
          # notch of the open last one, as in the JAR.
          def label(change, left, right, top, closed)
            x, anchor = if closed
                          [(left + right) / 2, "middle"]
                        else
                          [left + TIP, "start"]
                        end
            @pen.text(change.state, x,
                      Drawing::Face.middle(top + SEGMENT_MIDDLE + 4.54, 12),
                      anchor: anchor, size: 12, bold: true, fill: INK)
          end

          def hexagon(left, right, top, closed)
            upper = top + SEGMENT_MIDDLE - 12.0
            lower = top + SEGMENT_MIDDLE + 12.0
            middle = top + SEGMENT_MIDDLE
            notch = [[left + TIP, upper], [left, middle], [left + TIP, lower]]
            unless closed
              return polygon_path([[right, upper]] + notch + [[right, lower]],
                                  false)
            end

            polygon_path(notch + [[right - TIP, lower], [right, middle],
                                  [right - TIP, upper]], true)
          end

          # The open last segment has no edge at the right, as in the JAR.
          def polygon_path(points, closed)
            commands = points.each_with_index.map do |(x, y), index|
              { type: index.zero? ? :move : :line, x: x, y: y }
            end
            closed ? commands << { type: :close } : commands
          end

          def draw_analog(participant, top)
            points = analog_points(participant, top)
            return if points.empty?

            commands = points.each_with_index.map do |(time, y), index|
              [index.zero? ? :move : :line, @axis.x(time), y]
            end
            @pen.path(commands + [[:line, @axis.x(@axis.finish),
                                   points.last[1]]], stroke: INK,
                                                     stroke_width: "0.5")
          end

          def analog_points(participant, top)
            low, high = values(participant).minmax
            range = high > low ? high - low : 1.0
            changes(participant).map do |change|
              share = (change.state.to_f - low) / range
              [change.time, analog_y(participant, top, share)]
            end
          end

          def analog_y(_participant, top, share)
            top + ANALOG_LOW - (share * (ANALOG_LOW - HIGH))
          end
        end
      end
    end
  end
end
