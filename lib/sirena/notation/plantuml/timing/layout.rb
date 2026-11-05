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

          TOP = 20.0
          MARGIN = 20.0
          # Past the last tick the lanes' frame runs this far; below the
          # axis the canvas keeps this much (tick, label and margin).
          REACH = 5.0
          FOOT = 33.0
          PLOT = 420.0
          MIN_LEFT = 25.0
          RULE = "#333333"
          TAB_HEIGHT = 17.5
          TAB_SLANT = 10.0
          GRID = "3,5"
          private_constant :TOP, :PLOT, :MIN_LEFT, :RULE, :GRID,
                           :TAB_HEIGHT, :TAB_SLANT, :MARGIN, :REACH, :FOOT

          # @param diagram [Diagram]
          # @return [Drawing::Scene]
          def call(diagram, **)
            @diagram = diagram
            prepare
            draw_backdrop
            draw_foreground
            scene(canvas_width, @bottom + FOOT)
          end

          private

          def prepare
            @left = left_width
            @axis = Axis.new(@diagram, @left, PLOT)
            @signals = Signals.new(self, @diagram, @axis, @left)
            @tracks = stack
            @bottom = @tracks.values.map { |top, size| top + size }.max || TOP
            @right = @axis.x(@axis.finish) + REACH
          end

          # PlantUML counts a whole pixel past the right margin, and makes
          # room for the widest lane name's tab.
          def canvas_width
            tabs = @diagram.participants.values.map { |p| tab_edge(p.title) }
            ([@right, tabs.max.to_f + TAB_SLANT].max + MARGIN).floor + 1
          end

          def left_width
            signals = Signals.new(self, @diagram, nil, 0)
            leads = @diagram.participants.values.map { |p| signals.lead(p) }
            [leads.max.to_f, MIN_LEFT].max
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
            sides
            arrows = Arrows.new(self, @axis, method(:signal_point))
            @diagram.messages.each { |message| arrows.draw(message) }
            axis_line
            @diagram.highlights.each { |highlight| caption(highlight) }
          end

          def sides
            [MARGIN, @right].each do |x|
              line(x, TOP, x, @bottom, stroke: RULE, stroke_width: "0.5")
            end
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
            line(across, TOP, across, @bottom, stroke: RULE,
                                               stroke_width: "0.5",
                                               stroke_dasharray: GRID)
          end

          def track(participant)
            top, = @tracks.fetch(participant.id)
            frame(participant.title, top)
            @signals.draw_labels(participant, top)
            @signals.draw(participant, top)
          end

          def frame(title, top)
            line(MARGIN, top, @right, top, stroke: RULE, stroke_width: "0.5")
            text(title, MARGIN + 5, top + 8.75, size: 14, bold: true,
                                                fill: RULE)
            tab(title, top)
          end

          # The outline PlantUML draws round a lane's name: a rule under the
          # text that slants up to the lane's top edge.
          def tab(title, top)
            edge = tab_edge(title)
            low = top + TAB_HEIGHT
            line(MARGIN, low, edge, low, stroke: RULE, stroke_width: "0.5")
            line(edge, low, edge + TAB_SLANT, top, stroke: RULE,
                                                   stroke_width: "0.5")
          end

          def tab_edge(title)
            MARGIN + 6 + Drawing::Face.lucida_width(title, size: 14, bold: true)
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

            text(@axis.label(time), x, @bottom + 12.87, size: 11,
                                                        anchor: "middle",
                                                        fill: RULE)
          end
        end
      end
    end
  end
end
