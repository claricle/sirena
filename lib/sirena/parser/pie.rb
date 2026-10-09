# frozen_string_literal: true

require_relative "base"
require_relative "grammars/pie"
require_relative "builders/pie"
require_relative "../diagram/pie"

module Sirena
  module Parser
    # Pie chart parser for Mermaid pie diagram syntax.
    #
    # Uses Parslet grammar-based parsing to handle pie chart syntax
    # with labeled data entries and numeric values.
    #
    # Parses pie charts with support for:
    # - Title declarations
    # - showData flag for displaying values
    # - Data entries with quoted labels and numeric values
    # - Accessibility features (accTitle, accDescr)
    # - Comments
    #
    # @example Parse a simple pie chart
    #   parser = Pie.new
    #   diagram = parser.parse("pie\n  \"Apples\" : 42\n  \"Oranges\" : 58")
    class Pie < Base
      grammar Grammars::Pie
      builder Builders::Pie
    end
  end
end
