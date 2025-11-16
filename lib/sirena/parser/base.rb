# frozen_string_literal: true

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
    end

    # Error raised during parsing.
    class ParseError < StandardError; end
  end
end
