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
    # - Direction statements (TB, BT, LR, RL)
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
        tree = parse_with_grammar(Grammars::StateDiagram.new, source)
        Transforms::StateDiagram.new.apply(tree)
      end

      private

      # Formats a Parslet parse error with context.
      #
      # No rescue around this, unlike flowchart's copy. `Cause#pos` is a
      # `Parslet::Position` at every one of parslet 3.0.0's construction
      # sites, which is what `failure_position` reads; the shape the old
      # hand-rolled formatter here assumed — the Fixnum the gem's own
      # docstring still promises — does not occur, and every failure this
      # grammar can produce was run through this method to confirm it.
      #
      # @param cause [Parslet::Cause] the deepest failure
      # @param source [String] the source that failed to parse
      # @return [String] formatted error message
      def format_parse_error(cause, source)
        lines = source.lines("\n")
        line_num, col_num = failure_position(cause, source)

        context = if line_num <= lines.length
                    lines[line_num - 1].chomp("\n")
                  else
                    '(end of input)'
                  end

        "Parse error at line #{line_num}, column #{col_num}:\n" \
          "#{context}\n" \
          "#{caret_for(lines[line_num - 1], col_num)}\n" \
          "#{failure_message(cause)}"
      end
    end
  end
end
