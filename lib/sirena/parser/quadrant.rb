# frozen_string_literal: true

require_relative "base"
require_relative "grammars/quadrant"
require_relative "builders/quadrant"
require_relative "../diagram/quadrant"

module Sirena
  module Parser
    # Quadrant chart parser for Mermaid quadrant diagram syntax.
    #
    # Uses Parslet grammar-based parsing to handle quadrant chart syntax
    # with axis labels, quadrant labels, and data points.
    #
    # Parses quadrant charts with support for:
    # - Title declarations
    # - X-axis and Y-axis labels
    # - Quadrant labels (1-4)
    # - Data points with normalized coordinates
    # - Point styling (radius, color, stroke)
    # - Comments
    #
    # @example Parse a simple quadrant chart
    #   parser = Quadrant.new
    #   source = <<~MERMAID
    #     quadrantChart
    #       title Product Analysis
    #       x-axis Low Cost --> High Cost
    #       y-axis Low Value --> High Value
    #       Product A: [0.3, 0.7]
    #   MERMAID
    #   diagram = parser.parse(source)
    class Quadrant < Base
      grammar Grammars::Quadrant
      builder Builders::Quadrant
    end
  end
end
