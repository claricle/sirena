# frozen_string_literal: true

require_relative "base"
require_relative "grammars/architecture"
require_relative "transforms/architecture"

module Sirena
  module Parser
    # Parser for architecture diagrams
    class Architecture < Base
      def parse(input)
        # Not stripped: the grammar already allows leading and trailing
        # whitespace, and stripping shifted every reported line number by
        # however many blank lines the caller wrote.
        tree = parse_with_grammar(Grammars::Architecture.new, input)

        Transforms::Architecture.new.apply(tree)
      end

      private

      def format_parse_error(cause, input)
        lines = input.split("\n")
        line_no, column = failure_position(cause)

        context = []
        context << lines[line_no - 2] if line_no > 1
        context << lines[line_no - 1] if line_no > 0
        context << " " * (column - 1) + "^"

        "Parse error at line #{line_no}, column #{column}:\n" \
        "#{context.join("\n")}\n" \
        "#{cause.message}"
      end
    end
  end
end