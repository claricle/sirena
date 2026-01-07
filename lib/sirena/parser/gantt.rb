# frozen_string_literal: true

require_relative "base"
require_relative "grammars/gantt"
require_relative "transforms/gantt"
require_relative "../diagram/gantt"

module Sirena
  module Parser
    # Gantt chart parser for Mermaid gantt diagram syntax.
    #
    # Uses Parslet grammar-based parsing to handle Gantt chart syntax
    # with sections, tasks, dependencies, and timeline configuration.
    #
    # Parses Gantt charts with support for:
    # - Title and date format declarations
    # - Axis formatting and tick intervals
    # - Excludes (weekends, weekdays, specific dates)
    # - Section grouping
    # - Tasks with dates, durations, and dependencies
    # - Task status tags (done, active, crit, milestone)
    # - Click handlers for interactivity
    # - Accessibility features (accTitle, accDescr)
    # - Comments
    #
    # @example Parse a simple Gantt chart
    #   parser = GanttParser.new
    #   diagram = parser.parse(<<~GANTT)
    #     gantt
    #       title Project Timeline
    #       dateFormat YYYY-MM-DD
    #       section Planning
    #       Task 1 :a1, 2024-01-01, 30d
    #       Task 2 :after a1, 20d
    #   GANTT
    class GanttParser < Base
      # Parses Gantt chart diagram source into a GanttChart diagram model.
      #
      # @param source [String] the Mermaid Gantt chart diagram source
      # @return [Diagram::GanttChart] the parsed Gantt chart diagram
      # @raise [ParseError] if syntax is invalid
      def parse(source)
        grammar = Grammars::Gantt.new

        begin
          parse_tree = grammar.parse(source)
        rescue Parslet::ParseFailed => e
          raise ParseError, "Syntax error at #{e.parse_failure_cause.pos}: " \
                           "#{e.parse_failure_cause}"
        end

        # Transform parse tree to diagram model
        transform = Transforms::Gantt.new
        diagram = transform.apply(parse_tree)

        diagram
      end
    end
  end
end