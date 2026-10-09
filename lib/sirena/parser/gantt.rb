# frozen_string_literal: true

require_relative "base"
require_relative "grammars/gantt"
require_relative "builders/gantt"
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
    #   parser = Gantt.new
    #   diagram = parser.parse(<<~GANTT)
    #     gantt
    #       title Project Timeline
    #       dateFormat YYYY-MM-DD
    #       section Planning
    #       Task 1 :a1, 2024-01-01, 30d
    #       Task 2 :after a1, 20d
    #   GANTT
    class Gantt < Base
      grammar Grammars::Gantt
      builder Builders::Gantt
    end
  end
end
