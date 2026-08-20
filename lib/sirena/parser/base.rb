# frozen_string_literal: true

require 'parslet'

module Sirena
  module Parser
    # Abstract base class for diagram parsers.
    #
    # This class defines the interface that all diagram-specific parsers
    # must implement. Parsers are responsible for converting source code
    # into a typed diagram model using Parslet grammars.
    #
    # @example Define a custom parser
    #   class FlowchartParser < Parser::Base
    #     def parse(source)
    #       grammar = Grammars::Flowchart.new
    #       tree = grammar.parse(source)
    #       transform = Transforms::Flowchart.new
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
      # @return [Hash] the parse tree
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
        Array(cause.message).map { |part| message_part(part) }.join
      end

      # Parslet quotes a Slice and leaves everything else alone. Quoting by
      # "not a String" instead would render a lookahead's symbol as
      # `"LINE_END"` where parslet writes `LINE_END`.
      #
      # Deliberately unguarded by a spec: across 400 corpus files and all
      # five grammars, every message part is a String or a Slice, so the
      # third case is not reachable through any parser here. Matching
      # parslet is still the right rendering; a spec for it would have to
      # fabricate a cause and would prove nothing about real input.
      def message_part(part)
        part.respond_to?(:to_slice) ? part.str.inspect : part.to_s
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
        lines = source.lines
        preceding = lines[0, line - 1].to_a.join
        offset = cause.pos.bytepos - preceding.bytesize

        [line, lines[line - 1].to_s.byteslice(0, offset).to_s.length + 1]
      end
    end

    # Error raised during parsing.
    class ParseError < StandardError; end
  end
end
