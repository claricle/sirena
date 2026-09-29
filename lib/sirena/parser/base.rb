# frozen_string_literal: true

require 'parslet'
require_relative '../error'
require_relative '../error/parse_error'

module Sirena
  module Parser
    # Abstract base class for diagram parsers.
    #
    # This class defines the interface that all diagram-specific parsers
    # must implement. Parsers are responsible for converting source code
    # into a typed diagram model using Parslet grammars.
    #
    # @example Define a custom parser
    #   class Flowchart < Parser::Base
    #     def parse(source)
    #       grammar = Grammars::Flowchart.new
    #       tree = grammar.parse(source)
    #       transform = Builders::Flowchart.new
    #       transform.apply(tree)
    #     end
    #   end
    #
    # @abstract Subclass and implement #parse
    class Base

      # Parses Mermaid source code into a diagram model.
      #
      # This method should be overridden by subclasses to implement
      # diagram-specific parsing logic using Parslet grammars.
      #
      # @param source [String] the Mermaid source code to parse
      # @return [Diagram::Base] the parsed diagram model
      # @raise [NotImplementedError] if not implemented by subclass
      def parse(source)
        raise NotImplementedError,
              "#{self.class} must implement #parse(source)"
      end

      private

      # Runs a grammar, raising ParseError with a positioned message.
      #
      # Uses Parslet's Deepest reporter. The outer `parse_failure_cause`
      # points at the statement boundary the grammar gave up on rather than
      # where the input actually stopped: for "graph TD\nA-->" it reports
      # line 2 column 1, while the deepest cause reports line 2 column 5.
      # The reporter has to be kept, because the exception still carries the
      # outer cause even when a Deepest reporter is in use.
      #
      # @param grammar [Parslet::Parser] the grammar to run
      # @param source [String] the source to parse
      # @return [Hash, Array] the parse tree — a Hash for a single
      #   captured node, an Array once a grammar repeats one
      # @raise [ParseError] with the failure position and context
      def parse_with_grammar(grammar, source)
        reporter = Parslet::ErrorReporter::Deepest.new
        grammar.parse(source, reporter: reporter)
      rescue Parslet::ParseFailed => e
        cause = reporter.deepest_cause || e.parse_failure_cause
        raise ParseError, format_parse_error(cause, source)
      end

      # Renders a failure's text without its position.
      #
      # Parslet's message is a String for some failures and an Array of
      # String and Slice parts for a literal mismatch. Interpolating the
      # array split the message across lines and printed a slice's byte
      # offset, while cause.to_s renders it properly but appends a
      # byte-counted position that contradicts the heading's column.
      #
      # @param cause [Parslet::Cause] the failure to describe
      # @return [String] the message alone
      def failure_message(cause)
        Array(cause.message).map { |part| message_part(part) }.join('')
      end

      # Parslet quotes a Slice and leaves everything else alone. Quoting by
      # "not a String" instead would render a lookahead's symbol as
      # `"LINE_END"` where parslet writes `LINE_END`.
      #
      # A lookahead failure is the third case, and it is reachable: for
      # "graph TD\nstyle A " parslet builds an Entity part and the message
      # reads `Input should not start with LINE_END`. Quoting it would have
      # printed the symbol as a string literal.
      #
      # @param part [String, Parslet::Slice, Object] one piece of a message
      # @return [String] the piece as parslet would render it
      def message_part(part)
        part.respond_to?(:to_slice) ? part.str.inspect : part.to_s
      end

      # The last resort, when positioning itself blew up. NOT `#{cause}`:
      # `Parslet::Cause#to_s` joins its parts with a zero-argument join, so
      # a multi-part message is corrupted when the caller has set `$,`.
      #
      # @param cause [Parslet::Cause] the failure to describe
      # @return [String] the message with parslet's own position
      def fallback_message(cause)
        line, column = cause.source.line_and_column(cause.pos)
        "Parse error: #{failure_message(cause)} at line #{line} " \
          "char #{column}."
      end

      # Locates a failure as a 1-based line and CHARACTER column.
      #
      # Parslet counts bytes, so a line holding any multibyte character
      # reports a column further right than the caret should sit — the
      # message then underlines the wrong character.
      #
      # @param cause [Parslet::Cause] the failure to locate
      # @param source [String] the source that was parsed
      # @return [Array(Integer, Integer)] 1-based line and character column
      def failure_position(cause, source)
        line, = cause.source.line_and_column(cause.pos)
        lines = source.lines("\n")
        preceding = lines[0, line - 1].to_a.join('')
        offset = cause.pos.bytepos - preceding.bytesize

        [line, lines[line - 1].to_s.byteslice(0, offset).to_s.length + 1]
      end

      # The caret has to sit under the character the column names once the
      # message is printed. Padding with spaces put it eight columns early
      # on a tab-indented line, so the prefix is carried through with its
      # tabs intact and everything else blanked.
      #
      # @param line [String, nil] the source line being pointed at
      # @param column [Integer] 1-based character column
      # @return [String] the padding and the caret
      def caret_for(line, column)
        "#{line.to_s[0, column - 1].to_s.gsub(/[^\t]/, ' ')}^"
      end

      # Used by block, flowchart and requirement: also checks `line_num`
      # is positive, and falls back to the non-contextual message if
      # formatting itself raises. #format_parse_error_unguarded (used by
      # class_diagram and state_diagram) has neither — keep them separate;
      # merging would change those two's behaviour. architecture keeps its
      # own separate implementation; do not fold it in, its message shape
      # differs (two lines of context, no rescue).
      #
      # @param cause [Parslet::Cause] the failure to describe
      # @param source [String] the source that was parsed
      # @return [String] the positioned, multi-line error message
      def format_parse_error_guarded(cause, source)
        lines = source.lines("\n")
        line_num, col_num = failure_position(cause, source)

        context = []
        context << "Parse error at line #{line_num}, column #{col_num}:"
        context << if line_num.positive? && line_num <= lines.length
                     lines[line_num - 1].chomp("\n")
                   else
                     '(end of input)'
                   end
        context << caret_for(lines[line_num - 1], col_num)
        context << failure_message(cause)
        context.join("\n")
      rescue StandardError
        fallback_message(cause)
      end

      # The shape class_diagram and state_diagram use: no positivity check,
      # no rescue fallback. See #format_parse_error_guarded for why this
      # stays a second, distinct method rather than being unified with it.
      #
      # @param cause [Parslet::Cause] the failure to describe
      # @param source [String] the source that was parsed
      # @return [String] the positioned, multi-line error message
      def format_parse_error_unguarded(cause, source)
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
