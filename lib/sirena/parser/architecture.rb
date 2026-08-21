# frozen_string_literal: true

require_relative "base"
require_relative "grammars/architecture"
require_relative "transforms/architecture"

module Sirena
  module Parser
    # Parser for architecture diagrams
    class Architecture < Base
      def parse(input)
        # Still stripped. The grammar tolerates leading and trailing
        # whitespace, but String#strip also removes \v, \f and \r, which
        # the grammar does not — dropping it changed which inputs parse at
        # all, not just where a failure is reported.
        #
        # The cost is that positions are relative to the stripped source, so
        # leading blank lines are not counted. That is a smaller wrong than
        # changing what the parser accepts, and it is the only parser here
        # with the problem.
        stripped = input.strip
        tree = parse_with_grammar(Grammars::Architecture.new, stripped)

        Transforms::Architecture.new.apply(tree)
      end

      private

      def format_parse_error(cause, input)
        lines = input.split("\n")
        line_no, column = failure_position(cause, input)

        context = []
        context << lines[line_no - 2] if line_no > 1
        context << lines[line_no - 1] if line_no > 0
        context << caret_for(lines[line_no - 1], column)

        "Parse error at line #{line_no}, column #{column}:\n" \
        "#{context.join("\n")}\n" \
        "#{failure_message(cause)}"
      end
    end
  end
end