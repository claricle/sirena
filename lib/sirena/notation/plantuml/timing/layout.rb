# frozen_string_literal: true

require_relative "../drawing"
require_relative "arrows"
require_relative "axis"
require_relative "signals"

module Sirena
  module Notation
    module PlantUML
      module Timing
        # Stacks one track per participant over a shared time axis, then
        # lays highlights behind, messages across and the axis beneath.
        class Layout
          include Drawing::Pen

          TOP = 10.0
          PLOT = 420.0
          MIN_LEFT = 70.0
          RULE = "#333333"
          TAB_HEIGHT = 17.5
          TAB_SLANT = 10.0
          GRID = "3,3"
          private_constant :TOP, :PLOT, :MIN_LEFT, :RULE, :GRID,
                           :TAB_HEIGHT, :TAB_SLANT

          # @param diagram [Diagram]
          # @return [Drawing::Scene]
          def call(diagram, **)
            @diagram = diagram
            prepare
            draw_backdrop
            draw_foreground
            scene(@axis.x(@axis.finish) + 20, @bottom + 40)
          end

          private

          def prepare
            @left = left_width
            @axis = Axis.new(@diagram, @left, PLOT)
            @signals = Signals.new(self, @diagram, @axis, @left)
            @tracks = stack
            @bottom = @tracks.values.map { |top, size| top + size }.max || TOP
          end

          def left_width
            signals = Signals.new(self, @diagram, nil, 0)
            names = @diagram.participants.values.flat_map do |participant|
              [participant.title] +
                signals.labels(participant, 0).map(&:first)
            end
            [names.map { |name| text_width(name, size: 14) }.max.to_f + 30,
             MIN_LEFT].max
          end

          def stack
            top = TOP
            @diagram.participants.to_h do |id, participant|
              size = @signals.height(participant)
              entry = [id, [top, size]]
              top += size
              entry
            end
          end

          def draw_backdrop
            @diagram.highlights.each { |highlight| shade(highlight) }
            @axis.ticks.each { |time| grid(@axis.x(time)) }
          end

          def draw_foreground
            @diagram.participants.each_value { |p| track(p) }
            arrows = Arrows.new(self, @axis, method(:signal_point))
            @diagram.messages.each { |message| arrows.draw(message) }
            axis_line
            @diagram.highlights.each { |highlight| caption(highlight) }
          end

          def signal_point(id, time)
            top, = @tracks.fetch(id)
            @signals.y_at(@diagram.participants.fetch(id), top, time)
          end

          def shade(highlight)
            left = @axis.x(highlight.from)
            right = @axis.x(highlight.to)
            rect(left, TOP, right - left, @bottom - TOP,
                 fill: highlight.fill || "#EEEEEE", stroke: "none")
            [left, right].each do |x|
              line(x, TOP, x, @bottom, stroke: highlight.stroke || "#555555",
                                       stroke_dasharray: "5,3",
                                       stroke_width: "1.5")
            end
          end

          def caption(highlight)
            highlight.caption.to_s.split("\\n").each_with_index do |entry, row|
              text(entry, @axis.x(highlight.from) + 4, TOP + 10 + (row * 14))
            end
          end

          def grid(across)
            line(across, TOP, across, @bottom, stroke: "#808080",
                                               stroke_width: "0.5",
                                               stroke_dasharray: GRID)
          end

          def track(participant)
            top, = @tracks.fetch(participant.id)
            frame(participant.title, top)
            @signals.labels(participant, top).each do |name, y|
              text(name, @left - 6, y, anchor: "end", fill: RULE)
            end
            @signals.draw(participant, top)
          end

          def frame(title, top)
            line(0, top, @axis.x(@axis.finish), top, stroke: RULE,
                                                     stroke_width: "0.5")
            text(title, 5, top + 8.75, size: 14, bold: true, fill: RULE)
            tab(title, top)
          end

          # The outline PlantUML draws round a lane's name: a rule under the
          # text that slants up to the lane's top edge.
          def tab(title, top)
            edge = 6 + text_width(title, size: 14)
            low = top + TAB_HEIGHT
            line(0, low, edge, low, stroke: RULE, stroke_width: "0.5")
            line(edge, low, edge + TAB_SLANT, top, stroke: RULE,
                                                   stroke_width: "0.5")
          end

          def axis_line
            line(@axis.x(@axis.start), @bottom, @axis.x(@axis.finish),
                 @bottom, stroke_width: "2", stroke: RULE)
            @axis.ticks.each { |time| tick(time) }
          end

          def tick(time)
            x = @axis.x(time)
            line(x, @bottom, x, @bottom + 5)
            return unless @axis.labelled?(time)

            text(@axis.label(time), x, @bottom + 16, size: 11,
                                                     anchor: "middle",
                                                     fill: RULE)
          end
        end
      end
    end
  end
end
