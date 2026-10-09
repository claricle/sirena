# frozen_string_literal: true

require_relative "base"
require_relative "grammars/sequence"
require_relative "builders/sequence"
require_relative "../diagram/sequence"

module Sirena
  module Parser
    # Sequence parser for Mermaid sequence diagram syntax.
    #
    # Uses Parslet grammar-based parsing to correctly handle complex arrow
    # patterns with activation modifiers (e.g., `->>+`, `-->>-`) that cannot
    # be parsed accurately with regex-based lexers.
    #
    # Parses sequence diagrams with support for:
    # - Participant declarations (participant, actor)
    # - Multiple message types with activation modifiers
    # - Activations and deactivations
    # - Notes (left of, right of, over)
    # - Control structures (loop, alt, opt, par, critical, break)
    # - Box grouping
    #
    # @example Parse a simple sequence diagram
    #   parser = Sequence.new
    #   diagram = parser.parse("sequenceDiagram\nAlice->>Bob: Hello")
    class Sequence < Base
      grammar Grammars::Sequence
      builder Builders::Sequence
    end
  end
end
