# frozen_string_literal: true

require "parslet"
require_relative "common"

module Sirena
  module Parser
    module Grammars
      # Grammar for parsing Mermaid xychart-beta syntax
      class XYChart < Common

        rule(:diagram_type) { str("xychart-beta") >> space? }

        # Common line patterns
        rule(:eol) { line_end }
        rule(:indent?) { space? }
        rule(:comment_line) { comment >> newline }
        rule(:empty_line) { space? >> newline }
        rule(:text) { match['[^"\n\r]'].repeat(1) }

        rule(:title_line) do
          str("title") >> space >> quoted_string.as(:title) >> eol
        end

        # X-axis: x-axis [jan, feb, mar] or x-axis "Label" [1, 2, 3]
        rule(:axis_value) do
          space? >>
            (integer.as(:value) | identifier.as(:value)) >>
            space?
        end

        rule(:axis_values) do
          str("[") >>
            axis_value >> (str(",") >> axis_value).repeat >>
            str("]")
        end

        rule(:x_axis_line) do
          str("x-axis") >>
            (space >> quoted_string.as(:x_label)).maybe >>
            space >> axis_values.as(:x_values) >>
            eol
        end

        # Y-axis: y-axis "Label" min --> max or y-axis min --> max
        rule(:range_separator) { str("-->") }

        rule(:y_axis_line) do
          str("y-axis") >>
            (space >> quoted_string.as(:y_label)).maybe >>
            space >> integer.as(:y_min) >>
            space >> range_separator >>
            space >> integer.as(:y_max) >>
            eol
        end

        # Dataset values: [1, 2, 3, 4] or [1.5, 2.7, 3.2]
        rule(:number_value) do
          space? >>
            (
              integer >> (str(".") >> match["0-9"].repeat(1)).maybe
            ).as(:value) >>
            space?
        end

        rule(:value_array) do
          str("[") >>
            number_value >> (str(",") >> number_value).repeat >>
            str("]")
        end

        # Line dataset: line [values]
        rule(:line_dataset) do
          str("line") >>
            space >> value_array.as(:line_values) >>
            eol
        end

        # Bar dataset: bar [values]
        rule(:bar_dataset) do
          str("bar") >>
            space >> value_array.as(:bar_values) >>
            eol
        end

        # Named dataset: dataset "Name" [values]
        rule(:named_dataset) do
          str("dataset") >>
            space >> quoted_string.as(:dataset_label) >>
            space >> value_array.as(:dataset_values) >>
            eol
        end

        rule(:dataset_line) do
          line_dataset | bar_dataset | named_dataset
        end

        rule(:statement) do
          indent? >> (
            title_line |
            x_axis_line |
            y_axis_line |
            dataset_line |
            comment_line |
            empty_line
          )
        end

        rule(:body) { statement.repeat }

        rule(:xychart_diagram) do
          diagram_type >> eol >>
            body.as(:statements)
        end

        root(:xychart_diagram)
      end
    end
  end
end