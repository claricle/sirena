# frozen_string_literal: true

require_relative "box"
require_relative "mark"

module Sirena
  module Notation
    module PlantUMLSalt
      # How PlantUML sizes and draws each salt widget. A widget hangs from
      # the top of its row. A button, field or droplist is as wide as its
      # label or eight units a character, whichever is more.
      module WidgetMarks
        TEXT_DROP = 7.6
        CHAR_WIDTH = 8.0
        LABEL_FILL = "#EEEEEE"
        TEXT_HEIGHT = 14.1328
        HEIGHTS = { button: 23.1328, droplist: 18.1328,
                    field: 16.1328 }.freeze
        # What a cell holds beyond the label span: the widget's own
        # padding and stroke, then the next column's offset.
        CELL_EXTRA = { button: 9.0, field: 7.0, droplist: 17.0 }.freeze

        BUTTON_INSET = 2.5
        BUTTON_EXTRA = 4.0
        BUTTON_HEIGHT = 18.1328
        BUTTON_DROP = 12.1
        BUTTON_RADIUS = 5.0
        BUTTON_WEIGHT = 2.5

        FIELD_EXTRA = 3.0
        FIELD_RULE_DROP = 14.1328
        FIELD_TICK_DROP = 11.1328
        FIELD_TICK_HEIGHT = 2.0

        LIST_EXTRA = 15.0
        LIST_HEIGHT = 17.1328
        LIST_DROP = 9.6
        LIST_DIVIDER = 4.0
        LIST_ARROW = [[7.0, 6.0], [13.0, 6.0], [10.0, 12.1328]].freeze

        TICK_SIZE = 10.0
        TICK_LEFT = 2.0
        TICK_TOP = 2.0664
        TICK_WEIGHT = 1.5
        TICK_LABEL = 20.0
        TICK_MARK = [[1, 3.9336], [4, 6.9336], [11, -2.0664],
                     [4, 4.9336]].freeze
        RADIO_RADIUS = 5.0
        RADIO_DOT = 2.0

        INK = "#000000"
        private_constant :INK

        private

        def widget_height(widget)
          HEIGHTS.fetch(widget.kind, TEXT_HEIGHT)
        end

        def widget_width(widget)
          label = runs_width(widget.runs)
          case widget.kind
          when :empty then 0.0
          when :text then label
          when :checkbox, :radio then TICK_LABEL + tick_label_width(label)
          else span(widget) + CELL_EXTRA.fetch(widget.kind)
          end
        end

        # Eight units a character, unless the label is wider.
        def span(widget)
          [widget.text.length * CHAR_WIDTH, runs_width(widget.runs)].max
        end

        def tick_label_width(label)
          label.positive? ? label : run_width(Run.new(" "))
        end

        def draw_widget(widget, left, top)
          case widget.kind
          when :empty then nil
          when :text then text(widget.runs, left, top + TEXT_DROP)
          when :button then button(widget, left, top)
          when :field then field(widget, left, top)
          when :droplist then droplist(widget, left, top)
          else ticked(widget, left, top)
          end
        end

        def button(widget, left, top)
          box = Box.new(left + BUTTON_INSET, top + BUTTON_INSET,
                        span(widget) + BUTTON_EXTRA, BUTTON_HEIGHT)
          @marks << pane(box, BUTTON_WEIGHT, BUTTON_RADIUS)
          button_label(widget, box.left, top + BUTTON_DROP)
        end

        # The label is centred in the box, inside its two-pixel padding.
        def button_label(widget, left, drop)
          room = span(widget) - runs_width(widget.runs)
          text(widget.runs, left + (BUTTON_EXTRA / 2) + (room / 2), drop)
        end

        def pane(box, weight, radius = nil)
          Mark.new(:rect, box, fill: LABEL_FILL, ink: INK, weight: weight,
                               radius: radius)
        end

        def field(widget, left, top)
          text(widget.runs, left + FIELD_EXTRA, top + TEXT_DROP)
          underline(left + 1, top, span(widget) + FIELD_EXTRA)
        end

        # A rule with a short tick up from each end.
        def underline(left, top, reach)
          @marks << rule(left, top + FIELD_RULE_DROP, reach, 0.0)
          [left, left + reach].each { |x| tick(x, top) }
        end

        def tick(left, top)
          @marks << rule(left, top + FIELD_TICK_DROP, 0.0, FIELD_TICK_HEIGHT)
        end

        def droplist(widget, left, top)
          width = span(widget)
          @marks << pane(Box.new(left, top, width + LIST_EXTRA, LIST_HEIGHT),
                         1.0)
          text(widget.runs, left + 2, top + LIST_DROP)
          arrow(left + width, top)
        end

        # The bar and the triangle after the label.
        def arrow(left, top)
          @marks << rule(left + LIST_DIVIDER, top, 0.0, LIST_HEIGHT)
          points = LIST_ARROW.map { |dx, dy| [left + dx, top + dy] }
          @marks << Mark.new(:polygon, Box.new(left, top, 0.0, 0.0),
                             fill: INK, ink: INK, points: points)
        end

        def ticked(widget, left, top)
          if widget.kind == :radio
            radio(widget, left, top)
          else
            checkbox(widget, left, top)
          end
          text(widget.runs, left + TICK_LABEL, top + TEXT_DROP)
        end

        def checkbox(widget, left, top)
          box = Box.new(left + TICK_LEFT, top + TICK_TOP, TICK_SIZE, TICK_SIZE)
          @marks << Mark.new(:rect, box, ink: INK, weight: TICK_WEIGHT)
          return unless widget.checked

          points = TICK_MARK.map { |dx, dy| [box.left + dx, box.top + dy] }
          @marks << Mark.new(:polygon, box, fill: INK, ink: INK,
                                            weight: TICK_WEIGHT,
                                            points: points)
        end

        def radio(widget, left, top)
          centre = [left + 7.0, top + 7.0664]
          @marks << dot(centre, RADIO_RADIUS, "none")
          @marks << dot(centre, RADIO_DOT, INK) if widget.checked
        end

        def dot(centre, radius, fill)
          box = Box.new(centre[0] - radius, centre[1] - radius, radius * 2,
                        radius * 2)
          Mark.new(:ellipse, box, fill: fill, ink: INK, weight: TICK_WEIGHT)
        end
      end
    end
  end
end
