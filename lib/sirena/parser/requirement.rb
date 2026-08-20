# frozen_string_literal: true

require_relative 'base'
require_relative 'grammars/requirement'
require_relative 'transforms/requirement'
require_relative '../diagram/requirement'

module Sirena
  module Parser
    # Requirement diagram parser for Mermaid requirement diagram syntax.
    #
    # Parses requirement diagrams with support for:
    # - Requirements with properties (id, text, risk, verifymethod)
    # - Multiple requirement types (requirement, functionalRequirement, etc.)
    # - Elements with properties (type, docref)
    # - Relationships (contains, copies, derives, satisfies, verifies, refines, traces)
    # - Styling directives
    # - Class definitions and assignments
    #
    # @example Parse a simple requirement diagram
    #   parser = RequirementParser.new
    #   diagram = parser.parse("requirementDiagram\n  requirement test_req { id: 1 }")
    class RequirementParser < Base
      # Parses requirement diagram source into a RequirementDiagram model.
      #
      # @param source [String] the Mermaid requirement diagram source
      # @return [Diagram::RequirementDiagram] the parsed requirement diagram
      # @raise [ParseError] if syntax is invalid
      def parse(source)
        tree = parse_with_grammar(Grammars::Requirement.new, source)
        Transforms::Requirement.apply(tree)
      end

      private

      # Formats a Parslet parse error with context.
      #
      # @param error [Parslet::ParseFailed] the parse error
      # @param source [String] the source that failed to parse
      # @return [String] formatted error message
      def format_parse_error(cause, source)
        lines = source.lines
        line_num, col_num = failure_position(cause, source)

        context = []
        context << "Parse error at line #{line_num}, column #{col_num}:"

        # A failure at EOF sits one line past the source, so there is no line
        # to quote. Say so and still draw the caret rather than emitting a
        # heading with nothing under it.
        context << if line_num.positive? && line_num <= lines.length
                     lines[line_num - 1].chomp
                   else
                     '(end of input)'
                   end
        context << (' ' * (col_num - 1)) + '^'

        # Not cause.to_s: it appends parslet's own byte-counted position,
        # which contradicts the character column in the heading above on any
        # line holding a multibyte character.
        context << failure_message(cause)
        context.join("\n")
      rescue StandardError
        # Fallback to simple error message
        "Parse error: #{cause}"
      end
    end
  end
end