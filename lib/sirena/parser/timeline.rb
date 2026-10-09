# frozen_string_literal: true

require_relative "base"
require_relative "grammars/timeline"
require_relative "builders/timeline"
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
    #   parser = Timeline.new
    #   diagram = parser.parse(<<~TIMELINE)
    #     timeline
    #       title History of Social Media
    #       2002 : LinkedIn
    #       2004 : Facebook : Google
    #       2005 : YouTube
    #   TIMELINE
    class Timeline < Base
      grammar Grammars::Timeline
      builder Builders::Timeline
    end
  end
end
