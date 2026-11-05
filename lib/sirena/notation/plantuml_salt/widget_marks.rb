# frozen_string_literal: true

require_relative "box"
require_relative "font_metrics"
require_relative "mark"
require_relative "widget"

module Sirena
  module Notation
    module PlantUMLSalt
      # How PlantUML sizes and draws each salt widget. A widget hangs from
      # the top of its row. A button, field or droplist is as wide as its
      # label or eight units a character, whichever is more.
      module WidgetMarks
        FONT_SIZE = FontMetrics::SIZE
        # Where a size-12 text's baseline sits below the top of its row.
        BASELINE = FontMetrics::ASCENT
        CHAR_WIDTH = 8.0
        LABEL_FILL = "#EEEEEE"
        TEXT_HEIGHT = FontMetrics::HEIGHT
        # PlantUML never sizes a widget's text line under this, however
        # small the font: `<size:6>` rows are as tall as `<size:8>` ones.
        MIN_LINE = 10.0
        # Each widget is its text line plus the room its own drawing takes.
        EXTRA_HEIGHT = { button: 9.0, droplist: 4.0, field: 2.0 }.freeze
        RULE_HEIGHT = 6.0
        # What a cell holds beyond the label span: the widget's own
        # padding and stroke, then the next column's offset.
        CELL_EXTRA = { button: 9.0, field: 6.0, droplist: 16.0 }.freeze
        # What a drawn widget reaches past its cell: it counts toward the
        # canvas when nothing follows it, and falls in the gap otherwise.
        OVERHANG = 1.0e-6

        BUTTON_INSET = 2.5
        BUTTON_EXTRA = 4.0
        BUTTON_EXTRA_HEIGHT = 4.0
        BUTTON_DROP = 0.5
        BUTTON_RADIUS = 5.0
        BUTTON_WEIGHT = 2.5

        FIELD_EXTRA = 3.0
        FIELD_TICK_RISE = 3.0
        FIELD_TICK_HEIGHT = 2.0

        LIST_EXTRA = 15.0
        LIST_EXTRA_HEIGHT = 3.0
        LIST_DROP = -2.0
        LIST_DIVIDER = 4.0
        LIST_ARROW = [[7.0, 6.0], [13.0, 6.0], [10.0, -2.0]].freeze
        # An open droplist's choices, a box below the widget; one choice
        # is a line high, less a pixel.
        CHOICES_DROP = 3.0

        # A separator row is a rule in grey, drawn this far below its top:
        # (weight, dash, offsets of the strokes).
        RULE_INK = "#AAAAAA"
        RULE_DROP = 3.5
        RULE_BLEED = 1.0
        RULES = { dotted: [1.0, "1,2", [0.0]], double: [1.0, nil, [-1.0, 1.0]],
                  solid: [1.0, nil, [0.0]], heavy: [1.5, nil, [0.0]] }.freeze

        TICK_SIZE = 10.0
        TICK_LEFT = 2.0
        TICK_WEIGHT = 1.5
        TICK_LABEL = 20.0
        # The tick's points: right of the box's edge, below the row's top.
        TICK_MARK = [[1, 6.0], [4, 9.0], [11, 0.0], [4, 7.0]].freeze
        RADIO_RADIUS = 5.0
        RADIO_DOT = 2.0

        INK = "#000000"
        private_constant :INK

        private

        def widget_height(widget)
          return RULE_HEIGHT if widget.kind == :rule

          line_height(widget) + EXTRA_HEIGHT.fetch(widget.kind, 0.0)
        end

        # A line of text is as tall as its size asks, but never under
        # {MIN_LINE}.
        def line_height(widget)
          [unfloored_line(widget), MIN_LINE].max
        end

        def unfloored_line(widget)
          line_of(text_size(widget))
        end

        def line_of(size)
          TEXT_HEIGHT * size / FONT_SIZE
        end

        def ascent_of(size)
          BASELINE * size / FONT_SIZE
        end

        def descent_of(size)
          (TEXT_HEIGHT - BASELINE) * size / FONT_SIZE
        end

        def text_size(widget)
          runs_size(widget.runs)
        end

        def runs_size(runs)
          runs.filter_map(&:size).max || FONT_SIZE
        end

        def text_drop(widget)
          runs_drop(widget.runs)
        end

        # Where the baseline of `runs` sits below the top of their line.
        def runs_drop(runs)
          ascent_of(runs_size(runs)) - Mark::TEXT_LIFT
        end

        # Each run hangs from the bottom of the tallest one's line, so
        # runs of different sizes share a baseline.
        def text_runs(widget, left, top)
          rise = unfloored_line(widget) - Mark::TEXT_LIFT
          widget.runs.each do |run|
            left = text([run], left,
                        top + rise - descent_of(run.size || FONT_SIZE))
          end
        end

        def widget_width(widget)
          label = runs_width(widget.runs)
          case widget.kind
          when :rule then 0.0
          when :empty, :text then label
          when :checkbox, :radio then TICK_LABEL + tick_label_width(label)
          else span(widget) + CELL_EXTRA.fetch(widget.kind)
          end
        end

        # Eight units a character, unless the label is wider.
        def span(widget)
          [widget.chars * CHAR_WIDTH, runs_width(widget.runs)].max
        end

        # How far the widgets in the last column reach past it.
        def overhang(block, columns)
          return 0.0 if columns.empty?

          reach = block.rows.filter_map do |row|
            drawn_reach(row.cells[columns.size - 1])
          end
          [reach.max.to_f - columns.last, 0.0].max
        end

        def drawn_reach(cell)
          return unless cell.is_a?(Widget) && CELL_EXTRA.key?(cell.kind)

          widget_width(cell) + OVERHANG
        end

        def tick_label_width(label)
          label.positive? ? label : run_width(Run.new(" "))
        end

        def draw_widget(widget, left, top, reach)
          case widget.kind
          when :empty then nil
          when :rule then separator(widget, left, top, reach)
          when :text then text_runs(widget, left, top)
          when :button, :field, :droplist
            send(widget.kind, widget, left, top)
          else ticked(widget, left, top)
          end
        end

        def separator(widget, left, top, reach)
          weight, dash, offsets = RULES.fetch(widget.variant)
          offsets.each do |offset|
            @marks << rule(left, top + RULE_DROP + offset, reach + RULE_BLEED,
                           0.0, ink: RULE_INK, weight: weight, dash: dash)
          end
        end

        def button(widget, left, top)
          box = button_box(widget, left, top)
          @marks << pane(box, BUTTON_WEIGHT, BUTTON_RADIUS)
          button_label(widget, box.left,
                       top + ascent_of(text_size(widget)) + BUTTON_DROP)
        end

        def button_box(widget, left, top)
          Box.new(left + BUTTON_INSET, top + BUTTON_INSET,
                  span(widget) + BUTTON_EXTRA,
                  line_height(widget) + BUTTON_EXTRA_HEIGHT)
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
          text(widget.runs, left + FIELD_EXTRA, top + text_drop(widget))
          underline(left + 1, top, span(widget) + FIELD_EXTRA,
                    line_height(widget))
        end

        # A rule with a short tick up from each end.
        def underline(left, top, reach, line)
          @marks << rule(left, top + line, reach, 0.0)
          [left, left + reach].each do |x|
            tick(x, top + line - FIELD_TICK_RISE)
          end
        end

        def tick(left, top)
          @marks << rule(left, top, 0.0, FIELD_TICK_HEIGHT)
        end

        def droplist(widget, left, top)
          list(widget, left, top)
          overlay { choices(widget, left, top) } if widget.items.any?
        end

        def list(widget, left, top)
          line = line_height(widget)
          @marks << pane(list_box(widget, left, top, line), 1.0)
          text(widget.runs, left + 2,
               top + ascent_of(text_size(widget)) + LIST_DROP)
          arrow(left + span(widget), top, line)
        end

        def list_box(widget, left, top, line)
          Box.new(left, top, span(widget) + LIST_EXTRA,
                  line + LIST_EXTRA_HEIGHT)
        end

        # What the block draws on top of the layout, past its edge.
        def overlay
          from = @marks.size
          yield
          @overlays.concat(@marks.slice!(from..))
        end

        # The open droplist: one line a choice, as wide as the list or its
        # widest choice, less a pixel.
        def choices(widget, left, top)
          top += line_height(widget) + CHOICES_DROP
          @marks << pane(choices_box(widget, left, top), 1.0)
          widget.items.each_with_index do |item, index|
            text(item, left,
                 top + (index * TEXT_HEIGHT) + BASELINE - Mark::TEXT_LIFT)
          end
        end

        def choices_box(widget, left, top)
          wide = widget.items.map { |item| runs_width(item) }
          width = [span(widget) + LIST_EXTRA, *wide].max
          Box.new(left, top, width - 1,
                  (TEXT_HEIGHT * widget.items.size) - 1)
        end

        # The bar and the triangle after the label.
        def arrow(left, top, line)
          @marks << rule(left + LIST_DIVIDER, top, 0.0,
                         line + LIST_EXTRA_HEIGHT)
          points = LIST_ARROW.map do |dx, dy|
            [left + dx, top + (dy.negative? ? line + dy : dy)]
          end
          @marks << Mark.new(:polygon, Box.new(left, top, 0.0, 0.0),
                             fill: INK, ink: INK, points: points)
        end

        def ticked(widget, left, top)
          if widget.kind == :radio
            radio(widget, left, top)
          else
            checkbox(widget, left, top)
          end
          text(widget.runs, left + TICK_LABEL, top + text_drop(widget))
        end

        def checkbox(widget, left, top)
          box = Box.new(left + TICK_LEFT,
                        top + ((line_height(widget) - TICK_SIZE) / 2),
                        TICK_SIZE, TICK_SIZE)
          @marks << Mark.new(:rect, box, ink: INK, weight: TICK_WEIGHT)
          check_mark(box, top) if widget.checked
        end

        def check_mark(box, top)
          points = TICK_MARK.map { |dx, dy| [box.left + dx, top + dy] }
          @marks << Mark.new(:polygon, box, fill: INK, ink: INK,
                                            weight: TICK_WEIGHT,
                                            points: points)
        end

        def radio(widget, left, top)
          centre = [left + 7.0, top + (line_height(widget) / 2)]
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
