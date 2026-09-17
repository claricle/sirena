# frozen_string_literal: true

require_relative 'base'
require_relative 'grammars/flowchart'
require_relative 'transforms/flowchart'
require_relative '../diagram/flowchart'

module Sirena
  module Parser
    # Flowchart parser for Mermaid flowchart syntax.
    #
    # Parses flowchart diagrams with support for:
    # - Multiple node shapes (rectangle, rounded, rhombus, circle, etc.)
    # - Multiple edge types (arrow, line, dotted, etc.)
    # - Node labels with special characters
    # - Edge chaining (A --> B --> C)
    # - Subgraphs
    # - Styling directives
    # - Direction specification (TD, LR, etc.)
    #
    # @example Parse a simple flowchart
    #   parser = FlowchartParser.new
    #   diagram = parser.parse("graph TD\nA[Start]-->B[End]")
    class FlowchartParser < Base
      # Parses flowchart source into a Flowchart diagram model.
      #
      # @param source [String] the Mermaid flowchart source
      # @return [Diagram::Flowchart] the parsed flowchart
      # @raise [ParseError] if syntax is invalid
      def parse(source)
        # A lone CR is folded before the grammar sees it; the shared
        # helper owns the parse and the failure message.
        source = normalize_line_ends(source)
        Transforms::Flowchart.apply(parse_tree(source))
      end

      private

      # A deeply nested diagram runs the grammar past the stack. mmdc
      # renders 220 nested subgraphs and we refuse them, which is a gap —
      # but letting a StackError out of a parse is not a gap, it is a
      # crash in whatever called us.
      #
      # Only the grammar is wrapped. Both halves recurse, but the grammar
      # spends far more stack per nested box, so on a source anyone can
      # write it is the one that gives out first — measured here just
      # under 190 nested boxes, a tree the transform then walks without
      # trouble. A runaway recursion in the transform therefore stays
      # visible instead of being reported as a diagram that nests too
      # deeply. The depth moves with the stack the process was given, and
      # a tree built by hand rather than parsed can still outrun the
      # transform; neither changes which one a real source reaches first.
      #
      # @param source [String] the source with line ends already folded
      # @return [Hash, Array] the parse tree
      def parse_tree(source)
        parse_with_grammar(Grammars::Flowchart.new, source)
      rescue SystemStackError
        raise ParseError, 'Diagram nests too deeply to parse.'
      end

      # mermaid folds a CRLF and a lone CR into a newline before it reads
      # anything, so a bare `\r` ends a line, a comment and an accTitle's
      # text. The grammar's `newline` knows `\n` and `\r\n` only, and a
      # lone `\r` used to throw away a diagram mmdc draws.
      #
      # @param source [String] the Mermaid flowchart source
      # @return [String] the source with every line end as `\n`
      def normalize_line_ends(source)
        source.gsub(/\r\n?/, "\n")
      end

      # Formats a Parslet parse error with context.
      #
      # @param cause [Parslet::Cause] the deepest failure
      # @param source [String] the source that failed to parse
      # @return [String] formatted error message
      def format_parse_error(cause, source)
        lines = source.lines("\n")
        line_num, col_num = failure_position(cause, source)

        context = []
        context << "Parse error at line #{line_num}, column #{col_num}:"

        # A failure at EOF sits one line past the source, so there is no line
        # to quote. Say so and still draw the caret rather than emitting a
        # heading with nothing under it.
        context << if line_num.positive? && line_num <= lines.length
                     lines[line_num - 1].chomp("\n")
                   else
                     '(end of input)'
                   end
        context << caret_for(lines[line_num - 1], col_num)

        # Not cause.to_s: it appends parslet's own byte-counted position,
        # which contradicts the character column in the heading above on any
        # line holding a multibyte character.
        context << failure_message(cause)
        context.join("\n")
      rescue StandardError
        fallback_message(cause)
      end
    end
  end
end
