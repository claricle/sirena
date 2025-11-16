# frozen_string_literal: true

require_relative "base"
require_relative "../diagram/gantt"
require "date"

module Sirena
  module Transform
    # Gantt chart transformer for converting gantt models to renderable structure.
    #
    # Handles date calculations, dependency resolution, and timeline positioning.
    #
    # @example Transform a Gantt chart
    #   transform = GanttTransform.new
    #   data = transform.to_graph(gantt_diagram)
    class GanttTransform < Base
      # Converts a Gantt diagram to a layout structure with calculated positions.
      #
      # @param diagram [Diagram::GanttChart] the Gantt diagram to transform
      # @return [Hash] data structure for rendering
      # @raise [TransformError] if diagram is invalid
      def to_graph(diagram)
        @diagram = diagram
        @task_map = build_task_map(diagram)

        # Calculate dates for all tasks
        calculate_task_dates

        # Determine timeline range
        timeline = calculate_timeline

        {
          id: "gantt",
          title: diagram.title,
          date_format: diagram.date_format,
          axis_format: diagram.axis_format,
          tick_interval: diagram.tick_interval,
          excludes: diagram.excludes,
          today_marker: diagram.today_marker,
          sections: transform_sections(diagram, timeline),
          timeline: timeline,
          metadata: {
            section_count: diagram.sections.length,
            task_count: total_task_count(diagram)
          }
        }
      end

      private

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
        # First pass: calculate tasks with explicit dates
        @diagram.sections.each do |section|
          section.tasks.each do |task|
            calculate_task_date(task) if task.start_date && !task.after_task
          end
        end

        # Second pass: resolve dependencies
        max_iterations = 100
        iteration = 0
        loop do
          changed = false
          @diagram.sections.each do |section|
            section.tasks.each do |task|
              if !task.calculated_start && (task.after_task || task.until_task)
                if resolve_task_dependency(task)
                  changed = true
                end
              end
            end
          end

          iteration += 1
          break if !changed || iteration >= max_iterations
        end
      end

      def calculate_task_date(task)
        return if task.calculated_start

        if task.start_date
          task.calculated_start = parse_date(task.start_date)
        end

        if task.end_date
          task.calculated_end = parse_date(task.end_date)
        elsif task.duration && task.calculated_start
          task.calculated_end = add_duration(task.calculated_start, task.duration)
        end

        task.calculated_start
      end

      def resolve_task_dependency(task)
        if task.after_task
          ref_task = @task_map[task.after_task]
          return false unless ref_task && ref_task.calculated_end

          task.calculated_start = ref_task.calculated_end
          if task.duration
            task.calculated_end = add_duration(task.calculated_start, task.duration)
          elsif task.end_date
            task.calculated_end = parse_date(task.end_date)
          elsif task.until_task
            until_task = @task_map[task.until_task]
            task.calculated_end = until_task.calculated_start if until_task
          end
          return true
        end

        if task.until_task && task.start_date
          task.calculated_start = parse_date(task.start_date)
          until_task = @task_map[task.until_task]
          if until_task && until_task.calculated_start
            task.calculated_end = until_task.calculated_start
            return true
          end
        end

        false
      end

      def parse_date(date_str)
        # Handle various date formats
        Date.parse(date_str)
      rescue ArgumentError
        # Default to today if parsing fails
        Date.today
      end

      def add_duration(start_date, duration_str)
        # Parse duration string (e.g., "30d", "2w", "48h", "1M")
        value = duration_str.to_i
        unit = duration_str[-1]

        case unit
        when "d"
          start_date + value
        when "w"
          start_date + (value * 7)
        when "h"
          # Convert hours to days (rough approximation)
          start_date + (value / 24.0).ceil
        when "M"
          # Add months (rough approximation)
          start_date >> value
        else
          start_date + value # Default to days
        end
      end

      def calculate_timeline
        min_date = nil
        max_date = nil

        @diagram.sections.each do |section|
          section.tasks.each do |task|
            if task.calculated_start
              min_date = task.calculated_start if !min_date || task.calculated_start < min_date
            end
            if task.calculated_end
              max_date = task.calculated_end if !max_date || task.calculated_end > max_date
            end
          end
        end

        # Default to a reasonable range if no dates found
        min_date ||= Date.today
        max_date ||= Date.today + 30

        # Add padding
        min_date -= 1
        max_date += 1

        {
          start_date: min_date,
          end_date: max_date,
          total_days: (max_date - min_date).to_i
        }
      end

      def transform_sections(diagram, timeline)
        diagram.sections.map.with_index do |section, section_index|
          {
            id: "section_#{section_index}",
            name: section.name,
            tasks: transform_tasks(section, timeline, section_index)
          }
        end
      end

      def transform_tasks(section, timeline, section_index)
        section.tasks.map.with_index do |task, task_index|
          {
            id: task.id || "task_#{section_index}_#{task_index}",
            description: task.description,
            tags: task.tags,
            done: task.done?,
            active: task.active?,
            critical: task.critical?,
            milestone: task.milestone?,
            start_date: task.calculated_start,
            end_date: task.calculated_end,
            start_x: calculate_x_position(task.calculated_start, timeline),
            width: calculate_width(task.calculated_start, task.calculated_end, timeline),
            click_href: task.click_href,
            click_callback: task.click_callback
          }
        end
      end

      def calculate_x_position(date, timeline)
        return 0 unless date

        days_from_start = (date - timeline[:start_date]).to_i
        (days_from_start.to_f / timeline[:total_days]) * 800 # 800 is the timeline width
      end

      def calculate_width(start_date, end_date, timeline)
        return 20 unless start_date && end_date # Minimum width for milestones

        duration_days = (end_date - start_date).to_i
        return 10 if duration_days <= 0 # Milestone or zero duration

        (duration_days.to_f / timeline[:total_days]) * 800
      end

      def total_task_count(diagram)
        diagram.sections.sum { |s| s.tasks.length }
      end
    end
  end
end

# Extend GanttTask to hold calculated dates
module Sirena
  module Diagram
    class GanttTask
      attr_accessor :calculated_start, :calculated_end
    end
  end
end