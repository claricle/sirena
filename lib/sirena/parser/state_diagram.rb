# frozen_string_literal: true

require_relative 'base'
require_relative 'grammars/state_diagram'
require_relative 'transforms/state_diagram'
require_relative '../diagram/state_diagram'

module Sirena
  module Parser
    # State diagram parser for Mermaid state diagram syntax.
    #
    # Parses state diagrams with support for:
    # - Normal states with labels
    # - Special states (start [*], end [*], choice, fork, join)
    # - Transitions with triggers and guard conditions
    # - Composite/nested states
    # - Direction specification (TD, LR, etc.)
    #
    # @example Parse a simple state diagram
    #   parser = StateDiagramParser.new
    #   diagram = parser.parse("stateDiagram-v2\n[*]-->Idle\nIdle-->Active")
    class StateDiagramParser < Base
      # Parses state diagram source into a StateDiagram model.
      #
      # @param source [String] the Mermaid state diagram source
      # @return [Diagram::StateDiagram] the parsed state diagram
      # @raise [ParseError] if syntax is invalid
      def parse(source)
        grammar = Grammars::StateDiagram.new
        transform = Transforms::StateDiagram.new

        begin
          tree = grammar.parse(source)
          transform.apply(tree)
        rescue Parslet::ParseFailed => e
          raise ParseError, format_parse_error(e, source)
        end
      end

      private

      def format_parse_error(error, source)
        # Get the failure cause and position
        cause = error.parse_failure_cause
        pos = cause.pos

        # Get line and column - handle boundary conditions
        return "Parse error: #{error.message}" if pos.nil? || pos < 0 || pos > source.length

        lines = source[0...pos].split("\n")
        line_num = lines.size
        col_num = lines.last&.size || 0

        # Get the problematic line
        all_lines = source.split("\n")
        problem_line = all_lines[line_num - 1] || ''

        # Build error message
        msg = "Parse error at line #{line_num}, column #{col_num}\n"
        msg += "  #{problem_line}\n"
        msg += "  #{' ' * col_num}^\n" if col_num >= 0
        msg += "Expected: #{cause.expected_string}"
        msg
      rescue StandardError => e
        "Parse error: #{error.message} (#{e.message})"
      end
    end
  end
end
