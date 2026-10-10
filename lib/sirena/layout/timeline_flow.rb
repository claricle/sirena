# frozen_string_literal: true

require_relative "timeline_card"
require_relative "timeline_text"

module Sirena
  module Layout
    # Places timeline cards on mmdc's fixed grid: 200 units per period,
    # sections above their periods, events stacked under each period.
    #
    # Two numbers mmdc takes from a measuring pass are reproduced as it
    # takes them: every period is measured with the text "[object Object]"
    # (it passes the period object, not its name), and an event stack is
    # measured without the 50 unit minimum the drawn cards get.
    class TimelineFlow
      LEFT = 200
      TOP = 50
      COLUMN = 200
      TEXT_WIDTH = 150
      CARD_WIDTH = 190
      MIN_EVENT = 50
      EVENT_GAP = 10
      EVENT_DROP = 200
      PERIOD_MEASURE = "[object Object]"

      # @param groups [Array<Hash>] {name:, periods: [{name:, events:}]};
      #   one unnamed group when the diagram has no sections
      # @param sectioned [Boolean] whether groups are drawn as sections
      def initialize(groups, sectioned:)
        @groups = groups
        @sectioned = sectioned
        @periods = groups.flat_map { |group| group[:periods] }
      end

      # @return [Array<TimelineCard>] in drawing order
      def cards
        @cards ||= @sectioned ? sectioned_cards : unsectioned_cards
      end

      # @return [Float] y of the base arrow
      def axis_y
        return task_max + 100 unless @sectioned

        section_max + task_max + 150
      end

      private

      def unsectioned_cards
        period_cards(@periods, 0, [LEFT, TOP])
      end

      def sectioned_cards
        left = LEFT
        @groups.each_with_index.flat_map do |group, index|
          columns = [group[:periods].length, 1].max
          group_cards(group, index, left, columns).tap do
            left += COLUMN * columns
          end
        end
      end

      def group_cards(group, index, left, columns)
        origin = [left, TOP + section_max + 50]
        [section_card(group[:name], columns, index, left),
         *period_cards(group[:periods], index, origin)]
      end

      def section_card(name, columns, index, left)
        width = (COLUMN * columns) - 50
        lines = TimelineText.wrap(name, width)
        height = [TimelineText.card_height(lines), section_max].max
        card("section", lines, [left, TOP, width + 40, height], index)
      end

      def period_cards(periods, color, origin)
        running = task_max
        periods.flat_map.with_index do |period, index|
          card = period_card(period[:name], shifted(origin, index), running,
                             color)
          running = [running, card.height].max
          card.connector = connector(card, running, origin.last)
          [card, *event_cards(period[:events], card, color)]
        end
      end

      def shifted(origin, index)
        [origin.first + (COLUMN * index), origin.last]
      end

      def period_card(name, origin, running, color)
        lines = TimelineText.wrap(name, TEXT_WIDTH)
        height = [TimelineText.card_height(lines), running].max
        card("period", lines, [*origin, CARD_WIDTH, height], color)
      end

      def event_cards(events, period, color)
        top = period.y + EVENT_DROP
        events.map do |text|
          lines = TimelineText.wrap(text, TEXT_WIDTH)
          height = [TimelineText.card_height(lines), MIN_EVENT].max
          card("event", lines, [period.x, top, CARD_WIDTH, height], color)
            .tap { top += EVENT_GAP + height }
        end
      end

      def connector(period, running, top)
        TimelineLine.new(
          x1: period.x + 95, y1: top + running, x2: period.x + 95,
          y2: top + running + EVENT_DROP + event_stack_max,
          stroke_width: 2, dashed: true
        )
      end

      def card(kind, lines, box, color)
        x, y, width, height = box
        TimelineCard.new(
          kind: kind, lines: lines.reject(&:empty?), x: x, y: y,
          width: width, height: height, color_index: color,
          font_size: TimelineText::FONT_SIZE,
          text_width: lines.map { |line| TimelineText.width_of(line) }.max
        )
      end

      def section_max
        @section_max ||= @groups.map do |group|
          measured(group[:name]) + TimelineText::PADDING
        end.max.to_f
      end

      def task_max
        @task_max ||= @periods.empty? ? 0.0 : measured(PERIOD_MEASURE) + 20
      end

      def event_stack_max
        @event_stack_max ||=
          @periods.map { |period| stack(period[:events]) }.max.to_f
      end

      def stack(events)
        return 0 if events.empty?

        events.sum { |text| measured(text) } + (EVENT_GAP * (events.length - 1))
      end

      def measured(text)
        TimelineText.card_height(TimelineText.wrap(text, TEXT_WIDTH))
      end
    end
  end
end
