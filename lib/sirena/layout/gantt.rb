# frozen_string_literal: true

require_relative "base"
require_relative "gantt_ticks"
require_relative "gantt_duration"
require_relative "gantt_exclusions"
require_relative "../diagram/gantt"
require_relative "../notation/mermaid/ir_adapters/gantt"
require "date"

module Sirena
  module Layout
    # Gantt chart transformer for converting models to renderable structure.
    #
    # Handles date calculations, dependency resolution, and positioning.
    #
    # @example Transform a Gantt chart
    #   transform = Gantt.new
    #   data = transform.to_graph(gantt_diagram)
    class Gantt < Base
      MARGIN_LEFT = 200
      MARGIN_TOP = 80
      MARGIN_RIGHT = 50
      MARGIN_BOTTOM = 50
      ROW_HEIGHT = 40
      SECTION_HEIGHT = 30
      TASK_BAR_HEIGHT = 24
      TIMELINE_WIDTH = 800
      TIMELINE_HEIGHT = 40
      TITLE_Y = 40
      TIMELINE_PADDING_DAYS = 1
      DAY_SECONDS = 86_400
      DEFAULT_AXIS_FORMAT = "%Y-%m-%d"
      SCHEDULE_SETTINGS = %i[
        date_format axis_format tick_interval weekend inclusive_end_dates
        today_marker
      ].freeze
      TASK_PLACEMENTS = {
        id: "source_id", start_date: "start_date", end_date: "end_date",
        duration: "duration", after_task: "after_tasks",
        until_task: "until_task", click_href: "click_href",
        click_callback: "click_callback"
      }.freeze

      SourceDocument = Struct.new(
        :id, :title, :date_format, :axis_format, :tick_interval, :excludes,
        :weekend, :inclusive_end_dates, :today_marker, :acc_title,
        :acc_description, :sections, keyword_init: true
      )
      SourceSection = Struct.new(:name, :tasks, keyword_init: true)
      SourceTask = Struct.new(
        :description, :id, :start_date, :end_date, :duration, :after_task,
        :until_task, :tags, :click_href, :click_callback, :calculated_start,
        :calculated_end, :render_end, keyword_init: true
      ) do
        def done?
          tags.include?("done")
        end

        def active?
          tags.include?("active")
        end

        def critical?
          tags.include?("crit")
        end

        def milestone?
          tags.include?("milestone")
        end
      end
      private_constant :SourceDocument, :SourceSection, :SourceTask

      class Label < Lutaml::Model::Serializable
        attribute :text, :string
        attribute :x, :float
        attribute :y, :float
        attribute :text_anchor, :string
        attribute :font_size, :float
        attribute :font_weight, :string
        attribute :dominant_baseline, :string
      end

      class Rect < Lutaml::Model::Serializable
        attribute :x, :float
        attribute :y, :float
        attribute :width, :float
        attribute :height, :float
        attribute :corner_radius, :float
        attribute :kind, :string
      end

      class Line < Lutaml::Model::Serializable
        attribute :x1, :float
        attribute :y1, :float
        attribute :x2, :float
        attribute :y2, :float
      end

      class Task < Lutaml::Model::Serializable
        attribute :label, Label
        attribute :bar, Rect
        attribute :milestone_points, :string
        attribute :id_label, Label
        attribute :status, :string
        attribute :start_date, :date
        attribute :end_date, :date
      end

      class Section < Lutaml::Model::Serializable
        attribute :background, Rect
        attribute :label, Label
        attribute :tasks, Task, collection: true, default: -> { [] }
      end

      class Timeline < Lutaml::Model::Serializable
        attribute :background, Rect
        attribute :labels, Label, collection: true, default: -> { [] }
        attribute :grid_lines, Line, collection: true, default: -> { [] }
      end

      class Scene < Layout::Scene
        attribute :id, :string
        attribute :view_box, :string
        attribute :acc_title, :string
        attribute :acc_description, :string
        attribute :title, Label
        attribute :timeline, Timeline
        attribute :sections, Section, collection: true, default: -> { [] }
      end

      # Converts a Gantt diagram to a layout structure with calculated
      # positions.
      #
      # @param diagram [Diagram::Gantt] the Gantt diagram to transform
      # @return [Hash] data structure for rendering
      def build_graph(diagram)
        @diagram = source_document(ir_document(diagram))
        @task_map = build_task_map(@diagram)
        calculate_task_dates
        timeline = calculate_timeline
        schedule_attributes.merge(
          sections: transform_sections(@diagram, timeline),
          timeline: timeline,
          metadata: graph_metadata,
        )
      end

      private

      def scene(diagram)
        graph = build_graph(diagram)
        width = MARGIN_LEFT + TIMELINE_WIDTH + MARGIN_RIGHT
        height = scene_height(graph[:sections])
        Scene.new(**scene_attributes(graph, width, height))
      end

      def scene_attributes(graph, width, height)
        {
          id: graph[:id], width: width, height: height,
          view_box: "0 0 #{width} #{height}",
          acc_title: graph[:acc_title],
          acc_description: graph[:acc_description],
          title: title_geometry(graph[:title]),
          timeline: timeline_geometry(graph),
          sections: section_geometry(graph[:sections])
        }
      end

      def ir_document(diagram)
        return diagram if diagram.is_a?(IR::Prepositioned)

        Notation::Mermaid::IRAdapters::Gantt.call(diagram)
      end

      def source_document(document)
        settings = document.items.find do |item|
          item.role == "schedule_settings"
        end
        SourceDocument.new(
          **root_source_attributes(document),
          **schedule_setting_attributes(settings),
          excludes: children(document, settings&.id, "exclusion").map(&:label),
          sections: source_sections(document),
        )
      end

      def root_source_attributes(document)
        {
          id: document.id, title: document.label,
          acc_title: document.accessibility_title,
          acc_description: document.accessibility_description
        }
      end

      def schedule_setting_attributes(settings)
        SCHEDULE_SETTINGS.to_h do |name|
          [name, placement_value(settings, name.to_s)]
        end
      end

      def source_sections(document)
        children(document, nil, "section").sort_by { |item| source_order(item) }
          .map do |section|
            tasks = children(document, section.id, "task")
              .sort_by { |item| source_order(item) }
              .map { |task| source_task(document, task) }
            SourceSection.new(name: section.label, tasks: tasks)
          end
      end

      def source_task(document, item)
        attributes = TASK_PLACEMENTS.to_h do |name, dimension|
          [name, placement_value(item, dimension)]
        end
        attributes[:description] = item.label
        attributes[:tags] = source_tags(document, item)
        SourceTask.new(**attributes)
      end

      def source_tags(document, item)
        children(document, item.id, "status_flag")
          .sort_by { |status| source_order(status) }.map(&:label)
      end

      def schedule_attributes
        @diagram.to_h.slice(
          :id, :title, :acc_title, :acc_description, *SCHEDULE_SETTINGS,
          :excludes
        )
      end

      def graph_metadata
        {
          section_count: @diagram.sections.length,
          task_count: total_task_count(@diagram),
        }
      end

      def children(document, parent_id, role)
        document.items.select do |item|
          item.parent_id == parent_id && item.role == role
        end
      end

      def source_order(item)
        placement_value(item, "source_order") || 0
      end

      def placement_value(item, dimension)
        placement = item&.placements&.find do |candidate|
          candidate.dimension == dimension
        end
        placement&.value&.value
      end

      def scene_height(sections)
        total_rows = sections.sum { |section| section[:tasks].length + 1 }
        MARGIN_TOP + TIMELINE_HEIGHT + (total_rows * ROW_HEIGHT) + MARGIN_BOTTOM
      end

      def title_geometry(title)
        return unless title

        Label.new(text: title, x: MARGIN_LEFT + (TIMELINE_WIDTH / 2),
                  y: TITLE_Y, text_anchor: "middle",
                  font_size: large_font_size, font_weight: "bold")
      end

      def timeline_geometry(graph)
        timeline = graph[:timeline]
        Timeline.new(
          background: Rect.new(x: MARGIN_LEFT, y: MARGIN_TOP,
                               width: TIMELINE_WIDTH, height: TIMELINE_HEIGHT,
                               kind: "timeline"),
          labels: date_labels(timeline, graph[:axis_format],
                              graph[:tick_interval]),
          grid_lines: timeline_grid_lines(timeline, graph[:sections],
                                          graph[:tick_interval]),
        )
      end

      def date_labels(timeline, format, interval = nil)
        tick_positions(timeline, interval).map do |tick, position|
          date_label(tick, position, format)
        end
      end

      # [tick time, fraction of the timeline] pairs. The timeline is padded
      # by a day each side; mermaid's axis spans only the tasks, so ticks
      # are chosen from the unpadded range.
      def tick_positions(timeline, interval)
        days = timeline[:total_days]
        return [] if days <= 0

        start = timeline[:start_date]
        origin = start
        pad = TIMELINE_PADDING_DAYS * DAY_SECONDS
        stop = origin + (days * DAY_SECONDS) - pad
        GanttTicks.times(origin + pad, stop, interval).map do |tick|
          [tick, (tick - origin) / (days * DAY_SECONDS)]
        end
      end

      def date_label(date, position, format)
        Label.new(
          text: format_date(date, format),
          x: MARGIN_LEFT + (position * TIMELINE_WIDTH),
          y: MARGIN_TOP + TIMELINE_HEIGHT - 10,
          text_anchor: "middle", font_size: small_font_size
        )
      end

      def timeline_grid_lines(timeline, sections, interval)
        rows = sections.sum { |section| section[:tasks].length + 1 }
        tick_positions(timeline, interval).map do |_tick, position|
          timeline_grid_line(position, rows)
        end
      end

      def timeline_grid_line(position, rows)
        x = MARGIN_LEFT + (position * TIMELINE_WIDTH)
        y = MARGIN_TOP + TIMELINE_HEIGHT
        Line.new(x1: x, y1: y, x2: x, y2: y + (rows * ROW_HEIGHT))
      end

      def section_geometry(sections)
        next_y = MARGIN_TOP + TIMELINE_HEIGHT
        sections.map do |section|
          result = typed_section(section, next_y)
          next_y += SECTION_HEIGHT + (section[:tasks].length * ROW_HEIGHT)
          result
        end
      end

      def typed_section(section, header_y)
        task_y = header_y + SECTION_HEIGHT
        Section.new(
          background: section_background(header_y),
          label: section_label(section[:name], header_y),
          tasks: typed_tasks(section[:tasks], task_y),
        )
      end

      def section_background(header_y)
        Rect.new(
          x: 0, y: header_y,
          width: MARGIN_LEFT + TIMELINE_WIDTH + MARGIN_RIGHT,
          height: SECTION_HEIGHT, kind: "section"
        )
      end

      def section_label(name, header_y)
        Label.new(
          text: name, x: 10, y: header_y + (SECTION_HEIGHT / 2),
          font_size: normal_font_size, font_weight: "bold",
          dominant_baseline: "middle"
        )
      end

      def typed_tasks(tasks, first_y)
        tasks.map.with_index do |task, index|
          task_geometry(task, first_y + (index * ROW_HEIGHT))
        end
      end

      def task_geometry(task, row_position)
        x_coordinate, y_coordinate = task_position(task, row_position)
        Task.new(
          label: task_label(task, row_position),
          bar: task_bar(task, x_coordinate, y_coordinate),
          milestone_points: task_milestone(task, x_coordinate, y_coordinate),
          id_label: task_id_label(task, x_coordinate, y_coordinate),
          status: task_status(task),
          start_date: task[:start_date], end_date: task[:end_date]
        )
      end

      def task_position(task, row_position)
        x_coordinate = MARGIN_LEFT + task[:start_x]
        y_coordinate = row_position + ((ROW_HEIGHT - TASK_BAR_HEIGHT) / 2)
        [x_coordinate, y_coordinate]
      end

      def task_label(task, row_position)
        Label.new(
          text: task[:description], x: 10,
          y: row_position + (ROW_HEIGHT / 2),
          font_size: small_font_size, dominant_baseline: "middle"
        )
      end

      def task_bar(task, x_coordinate, y_coordinate)
        return if milestone?(task)

        Rect.new(
          x: x_coordinate, y: y_coordinate, width: task[:width],
          height: TASK_BAR_HEIGHT, corner_radius: 3, kind: "task"
        )
      end

      def task_milestone(task, x_coordinate, y_coordinate)
        return unless milestone?(task)

        milestone_points(x_coordinate, y_coordinate)
      end

      def milestone?(task)
        task[:milestone] || task[:width] < 10
      end

      def milestone_points(x_coordinate, y_coordinate)
        center_y = y_coordinate + (TASK_BAR_HEIGHT / 2)
        size = 12
        [[x_coordinate, center_y],
         [x_coordinate + size, center_y - size],
         [x_coordinate + (size * 2), center_y],
         [x_coordinate + size, center_y + size]]
          .map { |point| point.join(",") }.join(" ")
      end

      def task_id_label(task, x_coordinate, y_coordinate)
        return unless task[:id] && task[:width] > 40

        Label.new(
          text: task[:id], x: x_coordinate + (task[:width] / 2),
          y: y_coordinate + (TASK_BAR_HEIGHT / 2), text_anchor: "middle",
          font_size: small_font_size, dominant_baseline: "middle"
        )
      end

      def task_status(task)
        return "critical" if task[:critical]
        return "done" if task[:done]
        return "active" if task[:active]

        "default"
      end

      def format_date(date, format)
        return date.strftime(DEFAULT_AXIS_FORMAT) unless format

        date.strftime(format)
      rescue StandardError
        date.strftime(DEFAULT_AXIS_FORMAT)
      end

      def large_font_size
        theme.typography&.font_size_large ||
          Theme::Registry.get(:default).typography.font_size_large
      end

      def normal_font_size
        theme.typography&.font_size_normal ||
          Theme::Registry.get(:default).typography.font_size_normal
      end

      def small_font_size
        theme.typography&.font_size_small ||
          Theme::Registry.get(:default).typography.font_size_small
      end

      def build_task_map(diagram)
        map = {}
        diagram.sections.each do |section|
          section.tasks.each do |task|
            map[task.id] = task if task.id
          end
        end
        map
      end

      def calculate_task_dates
        tasks = @diagram.sections.flat_map(&:tasks)
        calculate_explicit_dates(tasks)
        resolve_dependencies(tasks)
      end

      def calculate_explicit_dates(tasks)
        tasks.each do |task|
          calculate_task_date(task) if task.start_date && !task.after_task
        end
      end

      # Resolve declared and implicit dependencies to a fixed point. An
      # implicit duration starts at the previous task's end, including across
      # sections and when that predecessor was itself resolved by dependency.
      def resolve_dependencies(tasks)
        100.times do
          break unless resolve_dependency_pass(tasks)
        end
      end

      def resolve_dependency_pass(tasks)
        changed = false
        tasks.each_with_index do |task, index|
          changed = true if resolve_unsettled_task?(task, tasks, index)
        end
        changed
      end

      def resolve_unsettled_task?(task, tasks, index)
        return false unless unresolved?(task)
        if task.after_task || task.until_task
          return resolve_task_dependency?(task)
        end
        return false unless task.duration && index.positive?

        chain_from_previous_task?(task, tasks[index - 1])
      end

      # A task with a start date but an "until" end is scheduled by the
      # first pass yet still waits for the until task's start.
      def unresolved?(task)
        return true unless task.calculated_start

        dated_until?(task) && task.calculated_end.nil?
      end

      def dated_until?(task)
        task.until_task && task.start_date && !task.after_task
      end

      # The predecessor is found by POSITION, not by id — the previous
      # task may have no id at all (ids are optional). Runs inside the
      # same fixed-point loop as `resolve_task_dependency?` so a chain
      # whose predecessor is itself still resolving (e.g. via its own
      # "after") converges once the predecessor does, instead of reading
      # a stale nil on the first pass.
      def chain_from_previous_task?(task, previous_task)
        return false unless previous_task.calculated_end

        task.calculated_start = previous_task.calculated_end
        settle_end(task, end_for(task.calculated_start, task.duration))
        true
      end

      def calculate_task_date(task)
        task.calculated_start = midnight(parse_date(task.start_date))
        settle_explicit_task_end(task)
      end

      def settle_explicit_task_end(task)
        if task.end_date
          settle_end(task, midnight(parse_date(task.end_date)))
        elsif task.duration && task.calculated_start
          settle_end(task, end_for(task.calculated_start, task.duration))
        end
      end

      def resolve_task_dependency?(task)
        return resolve_after_dependency?(task) if task.after_task

        resolve_until_dependency?(task)
      end

      def resolve_after_dependency?(task)
        ref_task = latest_dependency(task.after_task)
        return false unless ref_task

        task.calculated_start = ref_task.calculated_end
        settle_dependency_end(task)
        true
      end

      def settle_dependency_end(task)
        if task.duration
          settle_end(task, end_for(task.calculated_start, task.duration))
        elsif task.end_date
          settle_end(task, midnight(parse_date(task.end_date)))
        elsif task.until_task
          settle_until_end(task)
        end
      end

      def settle_until_end(task)
        until_task = @task_map[task.until_task]
        settle_end(task, until_task.calculated_start) if until_task
      end

      def resolve_until_dependency?(task)
        return false unless task.until_task && task.start_date

        task.calculated_start = midnight(parse_date(task.start_date))
        until_task = @task_map[task.until_task]
        return false unless until_task&.calculated_start

        settle_end(task, until_task.calculated_start)
        true
      end

      # "after a c" names every task this one waits on, space-separated —
      # mermaid starts it once ALL of them are done, i.e. after the LATEST
      # of their ends. Returns nil while any referenced id is unknown or has
      # not yet resolved its own end, so the caller's fixed-point loop tries
      # again on a later iteration instead of starting early on a partial
      # answer. A single id is just the one-element case of the same rule.
      def latest_dependency(after_task)
        ref_tasks = after_task.split.map { |id| @task_map[id] }
        return nil unless ref_tasks.all? { |ref_task| ref_task&.calculated_end }

        ref_tasks.max_by(&:calculated_end)
      end

      # Date.parse fills whatever the input omits from the system clock, so
      # "08/17" under `dateFormat MM/DD` picked up the real year and defeated
      # the injected reference date. Date._parse reports which fields the
      # input actually carried, so nothing here reads the clock.
      #
      # Which field comes from where: the year always comes from the reference
      # date when absent, and so does the month when no year was given. A
      # missing day becomes the 1st, and a missing month becomes January when
      # the year IS explicit — both to preserve what Date.parse returned, so
      # "2024/01" still reads as 2024-01-01 rather than moving with the pin.
      def parse_date(date_str)
        parts = Date._parse(date_str.to_s)
        return ordinal_date(parts) if parts[:yday]
        return today unless parts[:mon] || parts[:mday]

        Date.new(*calendar_date_parts(parts))
      rescue ArgumentError, TypeError
        today
      end

      # Ordinal dates carry a day-of-year instead of a month and day.
      def ordinal_date(parts)
        Date.ordinal(parts[:year] || today.year, parts[:yday])
      end

      # An explicit year defaults the month to January; without one, the
      # injected reference date supplies both year and month.
      def calendar_date_parts(parts)
        default_month = parts[:year] ? 1 : today.mon
        [parts[:year] || today.year, parts[:mon] || default_month,
         parts[:mday] || 1]
      end

      def end_for(start_time, duration_str)
        GanttDuration.add(start_time, duration_str)
      end

      def midnight(date)
        Time.utc(date.year, date.month, date.day)
      end

      # An end written as a YYYY-MM-DD date is final; every other end is
      # pushed past excluded days, as mermaid's checkTaskDates does.
      def settle_end(task, stop)
        if task.end_date.to_s.match?(/\A\d{4}-\d{2}-\d{2}\z/)
          task.calculated_end = stop
          task.render_end = nil
          return
        end

        task.calculated_end, task.render_end =
          exclusions.settle(task.calculated_start, stop)
      end

      def exclusions
        @exclusions ||= GanttExclusions.new(
          @diagram.excludes, @diagram.weekend, @diagram.date_format
        )
      end

      def calculate_timeline
        min_date, max_date = timeline_bounds
        min_date ||= midnight(today)
        max_date ||= midnight(today + 30)
        padded_timeline(min_date, max_date)
      end

      def timeline_bounds
        tasks = @diagram.sections.flat_map(&:tasks)
        starts = tasks.filter_map(&:calculated_start)
        finishes = tasks.filter_map(&:calculated_end)
        [starts.min, finishes.max]
      end

      def padded_timeline(min_date, max_date)
        start_date = min_date - DAY_SECONDS
        end_date = max_date + DAY_SECONDS
        {
          start_date: start_date, end_date: end_date,
          total_days: (end_date - start_date) / DAY_SECONDS
        }
      end

      def transform_sections(diagram, timeline)
        diagram.sections.map.with_index do |section, section_index|
          {
            id: "section_#{section_index}",
            name: section.name,
            tasks: transform_tasks(section, timeline, section_index),
          }
        end
      end

      def transform_tasks(section, axis, section_index)
        section.tasks.map.with_index do |task, task_index|
          transformed_task(task, axis, section_index, task_index)
        end
      end

      def transformed_task(task, axis, section_index, task_index)
        {
          id: task.id || "task_#{section_index}_#{task_index}",
          description: task.description, tags: task.tags,
          **task_flags(task), **task_timing(task, axis),
          click_href: task.click_href, click_callback: task.click_callback
        }
      end

      def task_flags(task)
        {
          done: task.done?, active: task.active?,
          critical: task.critical?, milestone: task.milestone?
        }
      end

      def task_timing(task, axis)
        {
          start_date: task.calculated_start&.to_date,
          end_date: task.calculated_end&.to_date,
          start_x: calculate_x_position(task.calculated_start, axis),
          width: task_width(task, axis),
        }
      end

      def calculate_x_position(date, timeline)
        return 0 unless date

        days_from_start = (date - timeline[:start_date]) / DAY_SECONDS
        # The timeline is 800 pixels wide.
        (days_from_start.to_f / timeline[:total_days]) * 800
      end

      def task_width(task, timeline)
        start_time = task.calculated_start
        end_time = task.render_end || task.calculated_end
        return 20 unless start_time && end_time # Minimum width for milestones

        duration_days = (end_time - start_time) / DAY_SECONDS
        return 10 if duration_days <= 0 # Milestone or zero duration

        (duration_days.to_f / timeline[:total_days]) * 800
      end

      def total_task_count(diagram)
        diagram.sections.sum { |s| s.tasks.length }
      end
    end
  end
end
