# frozen_string_literal: true

require_relative "common"

module Sirena
  module Parser
    module Grammars
      # Parslet grammar for Gantt chart diagrams.
      #
      # Handles Gantt chart syntax including title, date formatting,
      # sections, tasks with dependencies, and timeline configuration.
      #
      # @example Simple Gantt chart
      #   gantt
      #     title Project Timeline
      #     dateFormat YYYY-MM-DD
      #     section Planning
      #     Task 1 :a1, 2024-01-01, 30d
      #     Task 2 :after a1, 20d
      class Gantt < Common
        root(:diagram)

        # Main diagram structure
        rule(:diagram) do
          ws? >>
            header >>
            ws? >>
            statements.maybe >>
            ws?
        end

        # Header: gantt
        rule(:header) do
          str("gantt").as(:header) >> ws?
        end

        # Statements (configuration, sections, tasks, clicks)
        rule(:statements) do
          (ws? >> statement >> ws?).repeat(1)
        end

        rule(:statement) do
          acc_title_declaration |
            acc_descr_declaration |
            title_declaration |
            date_format_declaration |
            axis_format_declaration |
            tick_interval_declaration |
            excludes_declaration |
            today_marker_declaration |
            section_declaration |
            click_declaration |
            task_entry |
            comment
        end

        # Title
        rule(:title_declaration) do
          str("title") >> space.repeat(1) >>
            (line_end.absent? >> any).repeat(1).as(:title) >>
            line_end
        end

        # Date format
        rule(:date_format_declaration) do
          str("dateFormat") >> space.repeat(1) >>
            (line_end.absent? >> any).repeat(1).as(:date_format) >>
            line_end
        end

        # Axis format
        rule(:axis_format_declaration) do
          str("axisFormat") >> space.repeat(1) >>
            (line_end.absent? >> any).repeat(1).as(:axis_format) >>
            line_end
        end

        # Tick interval
        rule(:tick_interval_declaration) do
          str("tickInterval") >> space.repeat(1) >>
            (line_end.absent? >> any).repeat(1).as(:tick_interval) >>
            line_end
        end

        # Excludes (weekends, weekdays, or specific dates)
        rule(:excludes_declaration) do
          str("excludes") >> space.repeat(1) >>
            (line_end.absent? >> any).repeat(1).as(:excludes) >>
            line_end
        end

        # Today marker
        rule(:today_marker_declaration) do
          str("todayMarker") >> space.repeat(1) >>
            (line_end.absent? >> any).repeat(1).as(:today_marker) >>
            line_end
        end

        # Accessibility title
        rule(:acc_title_declaration) do
          str("accTitle") >> space? >> colon >> space? >>
            (line_end.absent? >> any).repeat.as(:acc_title) >>
            line_end
        end

        # Accessibility description (single or multi-line)
        rule(:acc_descr_declaration) do
          acc_descr_single_line | acc_descr_multi_line
        end

        rule(:acc_descr_single_line) do
          str("accDescr") >> space? >> colon >> space? >>
            (line_end.absent? >> any).repeat.as(:acc_descr) >>
            line_end
        end

        rule(:acc_descr_multi_line) do
          str("accDescr") >> space? >> lbrace >> ws? >>
            (rbrace.absent? >> any).repeat.as(:acc_descr) >>
            ws? >> rbrace >> line_end
        end

        # Section declaration
        rule(:section_declaration) do
          str("section") >> space.repeat(1) >>
            (line_end.absent? >> any).repeat(1).as(:section) >>
            line_end
        end

        # Click declaration for interactivity
        rule(:click_declaration) do
          str("click") >> space.repeat(1) >>
            identifier.as(:click_id) >>
            space.repeat(1) >>
            (click_href | click_callback) >>
            line_end
        end

        rule(:click_href) do
          str("href") >> space.repeat(1) >>
            (line_end.absent? >> any).repeat(1).as(:href)
        end

        rule(:click_callback) do
          str("call") >> space.repeat(1) >>
            (line_end.absent? >> any).repeat(1).as(:callback)
        end

        # Task entry with various formats
        rule(:task_entry) do
          (task_description.as(:description) >>
            space? >> colon >> space? >>
            task_details.as(:task_details) >>
            line_end).as(:task_entry)
        end

        rule(:task_description) do
          (colon.absent? >> line_end.absent? >> any).repeat(1)
        end

        # Task details can have multiple formats:
        # :tag, date, duration
        # :id, after other_id, duration
        # :id, start, end
        # :after id, duration
        # :duration
        rule(:task_details) do
          task_with_tags |
            task_with_id_and_dependency |
            task_with_dependency |
            task_with_dates |
            task_with_duration_only
        end

        # Task with tags (done, active, crit, milestone)
        rule(:task_with_tags) do
          tags.as(:tags) >>
            (space? >> comma >> space? >> task_timing).maybe
        end

        # Task with ID and after dependency (:id, after other_id, duration)
        rule(:task_with_id_and_dependency) do
          task_id.as(:id) >> space? >> comma >> space? >>
            str("after") >> space.repeat(1) >>
            task_id.as(:after_task) >>
            (space? >> comma >> space? >> (task_end_date | task_duration)).maybe
        end

        # Task with after dependency (after other_id, duration)
        rule(:task_with_dependency) do
          str("after") >> space.repeat(1) >>
            task_id.as(:after_task) >>
            (space? >> comma >> space? >> (task_end_date | task_duration)).maybe
        end

        # Task with until dependency
        rule(:task_with_until) do
          task_date.as(:start_date) >>
            comma >> space? >>
            str("until") >> space.repeat(1) >>
            task_id.as(:until_task)
        end

        # Task with explicit dates
        rule(:task_with_dates) do
          task_id.as(:id) >> space? >> comma >> space? >> task_timing
        end

        # Task with duration only
        rule(:task_with_duration_only) do
          space? >> task_timing
        end

        # Task timing (dates or duration)
        rule(:task_timing) do
          task_date.as(:start_date) >>
            (space? >> comma >> space? >> (task_end_date | task_duration)).maybe |
            task_duration.as(:duration)
        end

        rule(:task_end_date) do
          str("until") >> space.repeat(1) >> task_id.as(:until_task) |
            task_date.as(:end_date)
        end

        # Tags (space-separated only, no comma between tags)
        rule(:tags) do
          space? >> task_tag >> (space.repeat(1) >> task_tag).repeat
        end

        rule(:task_tag) do
          str("done") | str("active") | str("crit") | str("milestone")
        end

        # Task ID
        rule(:task_id) do
          match["a-zA-Z0-9_-"].repeat(1)
        end

        # Date in various formats (must contain date separator)
        rule(:task_date) do
          match["0-9"].repeat(1) >> match["-/:"] >> match["0-9-/:"].repeat
        end

        # Duration (e.g., 30d, 2w, 48h, 1M)
        rule(:task_duration) do
          match["0-9"].repeat(1) >> match["dwMh"]
        end
      end
    end
  end
end