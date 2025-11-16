# frozen_string_literal: true

require_relative "common"

module Sirena
  module Parser
    module Grammars
      # Parslet grammar for timeline diagrams.
      #
      # Handles timeline syntax including title, sections, events with
      # timestamps and descriptions, and accessibility features.
      #
      # @example Simple timeline
      #   timeline
      #     title History of Social Media
      #     2002 : LinkedIn
      #     2004 : Facebook : Google
      #     2005 : YouTube
      #
      # @example Timeline with sections
      #   timeline
      #     section 20th Century
      #       1903 : Wright Brothers flight
      #     section 21st Century
      #       2007 : iPhone released
      class Timeline < Common
        root(:diagram)

        # Main diagram structure
        rule(:diagram) do
          ws? >>
            header >>
            ws? >>
            statements.maybe >>
            ws?
        end

        # Header: timeline
        rule(:header) do
          str("timeline").as(:header) >> ws?
        end

        # Statements (title, sections, events, tasks)
        rule(:statements) do
          (statement >> ws?).repeat(1)
        end

        rule(:statement) do
          acc_title_declaration |
            acc_descr_declaration |
            title_declaration |
            section_declaration |
            event_entry |
            task_entry |
            comment >> line_end
        end

        # Title
        rule(:title_declaration) do
          str("title") >> space.repeat(1) >>
            (line_end.absent? >> any).repeat(1).as(:title) >>
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

        # Event entry: time : description(s)
        # Can have multiple descriptions separated by colons
        # Example: 2004 : Facebook : Google
        rule(:event_entry) do
          (space? >> event_time.as(:time) >>
            space? >> colon >>
            event_descriptions.as(:descriptions) >>
            line_end).as(:event_entry) |
            (space? >> colon >>
              event_descriptions.as(:descriptions) >>
              line_end).as(:continuation_entry)
        end

        # Event time (year, date, task name, or any time identifier)
        # Can include spaces, alphanumeric, and common punctuation
        rule(:event_time) do
          (colon.absent? >> line_end.absent? >> any).repeat(1)
        end

        # Event descriptions (one or more, separated by colons)
        rule(:event_descriptions) do
          event_description.as(:desc) >>
            (space? >> colon >> space? >> event_description.as(:desc)).repeat
        end

        # Single event description (can include HTML tags like <br>)
        rule(:event_description) do
          space? >>
            (colon.absent? >> line_end.absent? >> any).repeat(1) >>
            space?
        end

        # Task entry (plain text without colon, for sections)
        rule(:task_entry) do
          (colon.absent? >>
            str("section").absent? >>
            str("title").absent? >>
            str("accTitle").absent? >>
            str("accDescr").absent? >>
            line_end.absent? >>
            any).repeat(1).as(:task) >>
          line_end
        end
      end
    end
  end
end