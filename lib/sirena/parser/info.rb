# frozen_string_literal: true

require_relative "base"
require_relative "grammars/info"
require_relative "builders/info"
require_relative "../diagram/info"

module Sirena
  module Parser
    # Info diagram parser for Mermaid info diagram syntax.
    #
    # Uses Parslet grammar-based parsing to handle simple info diagrams.
    #
    # Parses info diagrams with support for:
    # - Basic info keyword
    # - Optional showInfo flag
    #
    # @example Parse a simple info diagram
    #   parser = Info.new
    #   diagram = parser.parse("info")
    #
    # @example Parse info diagram with showInfo
    #   parser = Info.new
    #   diagram = parser.parse("info showInfo")
    class Info < Base
      grammar Grammars::Info
      builder Builders::Info
    end
  end
end
