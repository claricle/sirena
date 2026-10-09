# frozen_string_literal: true

require_relative "base"
require_relative "grammars/error"
require_relative "builders/error"
require_relative "../diagram/error"

module Sirena
  module Parser
    # Error diagram parser for Mermaid error diagram syntax.
    #
    # Uses Parslet grammar-based parsing to handle simple error diagrams.
    #
    # Parses error diagrams with support for:
    # - Basic error keyword
    # - Optional error message text
    #
    # @example Parse a simple error diagram
    #   parser = Error.new
    #   diagram = parser.parse("error")
    #
    # @example Parse error diagram with message
    #   parser = Error.new
    #   diagram = parser.parse("Error Diagrams")
    class Error < Base
      grammar Grammars::Error
      builder Builders::Error
    end
  end
end
