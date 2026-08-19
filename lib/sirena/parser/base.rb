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

      # @param cause [Parslet::Cause] the failure to locate
      # @return [Array(Integer, Integer)] 1-based line and column
      def failure_position(cause)
        cause.source.line_and_column(cause.pos)
      end
    end

    # Error raised during parsing.
    class ParseError < StandardError; end
  end
end
