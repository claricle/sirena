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

        # Task details are a comma-separated list of fields, in any order
        # mermaid allows: status tags (done/active/crit/milestone), an id,
        # "after <id>", "until <id>", a date, and a duration. Mermaid itself
        # classifies each field by shape rather than by position, so the
        # grammar captures the raw fields and the transform (gantt.rb)
        # classifies them the same way.
        rule(:task_details) do
          (task_field.as(:field) >>
            (space? >> comma >> space? >> task_field.as(:field)).repeat).as(:parts)
        end

        rule(:task_field) do
          (comma.absent? >> line_end.absent? >> any).repeat(1)
        end
      end
    end
  end
end