# frozen_string_literal: true

require_relative "base"
require_relative "grammars/timeline"
require_relative "transforms/timeline"
require_relative "../diagram/timeline"

module Sirena
  module Parser
    # Timeline parser for Mermaid timeline diagram syntax.
    #
    # Uses Parslet grammar-based parsing to handle timeline syntax
    # with sections, events, and chronological ordering.
    #
    # Parses timelines with support for:
    # - Title declarations
    # - Section grouping (periods, categories)
    # - Events with timestamps and descriptions
    # - Multiple descriptions per timestamp
    # - Tasks within sections
    # - Accessibility features (accTitle, accDescr)
    # - Comments
    #
    # @example Parse a simple timeline
    #   parser = TimelineParser.new
    #   diagram = parser.parse(<<~TIMELINE)
    #     timeline
    #       title History of Social Media
    #       2002 : LinkedIn
    #       2004 : Facebook : Google
    #       2005 : YouTube
    #   TIMELINE
    class TimelineParser < Base
      # Parses timeline diagram source into a Timeline diagram model.
      #
      # @param source [String] the Mermaid timeline diagram source
      # @return [Diagram::Timeline] the parsed timeline diagram
      # @raise [ParseError] if syntax is invalid
      def parse(source)
        grammar = Grammars::Timeline.new

        begin
          parse_tree = grammar.parse(source)
        rescue Parslet::ParseFailed => e
          raise ParseError, "Syntax error at #{e.parse_failure_cause.pos}: " \
                           "#{e.parse_failure_cause}"
        end

        # Transform parse tree to diagram model
        transform = Transforms::Timeline.new
        diagram = transform.apply(parse_tree)

        diagram
      end
    end
  end
end