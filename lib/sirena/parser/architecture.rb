# frozen_string_literal: true

require_relative "base"
require_relative "grammars/architecture"
require_relative "transforms/architecture"

module Sirena
  module Parser
    # Parser for architecture diagrams
    class Architecture < Base
      def parse(input)
        input = input.strip

        grammar = Grammars::Architecture.new
        tree = grammar.parse(input)

        transform = Transforms::Architecture.new
        transform.apply(tree)
      rescue Parslet::ParseFailed => e
        raise ParseError, format_error(e, input)
      end

      private

      def format_error(error, input)
        lines = input.split("\n")
        line_no = error.parse_failure_cause.source.line_and_column[0]
        column = error.parse_failure_cause.source.line_and_column[1]

        context = []
        context << lines[line_no - 2] if line_no > 1
        context << lines[line_no - 1] if line_no > 0
        context << " " * (column - 1) + "^"

        "Parse error at line #{line_no}, column #{column}:\n" \
        "#{context.join("\n")}\n" \
        "#{error.parse_failure_cause.message}"
      end
    end
  end
end