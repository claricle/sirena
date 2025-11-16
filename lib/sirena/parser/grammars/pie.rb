# frozen_string_literal: true

require_relative 'common'

module Sirena
  module Parser
    module Grammars
      # Parslet grammar for pie chart diagrams.
      #
      # Handles pie chart syntax including title, data entries with labels
      # and numeric values, and accessibility features.
      #
      # @example Simple pie chart
      #   pie
      #     "Apples" : 42.5
      #     "Oranges" : 30.2
      #
      # @example Pie chart with title and showData
      #   pie title "Sales Report" showData
      #     "Q1" : 100
      #     "Q2" : 150
      class Pie < Common
        root(:diagram)

        # Main diagram structure
        rule(:diagram) do
          ws? >>
            header >>
            ws? >>
            statements.maybe >>
            ws?
        end

        # Header: pie|Pie|pie chart|Pie Chart [showData] [title <text>]
        rule(:header) do
          pie_keyword.as(:header) >>
            (space.repeat(1) >> show_data_flag).maybe.as(:show_data) >>
            (space.repeat(1) >> title_declaration).maybe.as(:title) >>
            ws?
        end

        # Pie keyword - case insensitive with optional "chart" suffix
        rule(:pie_keyword) do
          (match['Pp'] >> str('ie') >> (space.repeat(1) >> match['Cc'] >> str('hart')).maybe)
        end

        rule(:show_data_flag) do
          str('showData').as(:show_data)
        end

        rule(:title_declaration) do
          str('title') >> (colon | space.repeat(1)) >>
            title_text.as(:title)
        end

        rule(:title_text) do
          (line_end.absent? >> any).repeat
        end

        # Statements (can be data entries or accessibility declarations)
        rule(:statements) do
          (statement >> ws?).repeat(1)
        end

        rule(:statement) do
          acc_title_declaration |
            acc_descr_declaration |
            standalone_title_declaration |
            data_entry |
            comment >> line_end
        end

        # Title as a standalone statement (not in header)
        rule(:standalone_title_declaration) do
          # Allow escaped tabs and other whitespace
          (str('\\t') | space).repeat >>
            str('title') >> space.repeat(1) >>
            title_text.as(:standalone_title) >>
            line_end
        end

        # Accessibility title
        rule(:acc_title_declaration) do
          str('accTitle') >> space? >> colon >> space? >>
            (line_end.absent? >> any).repeat.as(:acc_title) >>
            line_end
        end

        # Accessibility description (single or multi-line)
        rule(:acc_descr_declaration) do
          acc_descr_single_line | acc_descr_multi_line
        end

        rule(:acc_descr_single_line) do
          str('accDescr') >> space? >> colon >> space? >>
            (line_end.absent? >> any).repeat.as(:acc_descr) >>
            line_end
        end

        rule(:acc_descr_multi_line) do
          str('accDescr') >> space? >> lbrace >> ws? >>
            (rbrace.absent? >> any).repeat.as(:acc_descr) >>
            ws? >> rbrace >> line_end
        end

        # Data entry: "label" : value
        # Allow escaped tabs in data entries
        rule(:data_entry) do
          (str('\\t') | space).repeat >>
            label_text.as(:label) >>
            (str('\\t') | space).repeat >> colon >> (str('\\t') | space).repeat >>
            numeric_value.as(:value) >>
            line_end.as(:data_entry)
        end

        # Label can be quoted string or unquoted text
        rule(:label_text) do
          quoted_string | single_quoted_string
        end

        # Numeric value (integer or decimal, can be negative)
        rule(:numeric_value) do
          minus.maybe >> (float | integer)
        end
      end
    end
  end
end