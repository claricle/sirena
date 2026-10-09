# frozen_string_literal: true

require_relative "base"
require_relative "grammars/block"
require_relative "builders/block"
require_relative "../diagram/block"

module Sirena
  module Parser
    # Block diagram parser for Mermaid block diagram syntax.
    #
    # Parses block diagrams with support for:
    # - Column-based layouts
    # - Blocks with various shapes (rectangle, circle)
    # - Block width specifications
    # - Compound/nested blocks
    # - Space placeholders
    # - Arrow blocks with directions
    # - Connections between blocks
    # - Styling directives
    #
    # @example Parse a simple block diagram
    #   parser = Block.new
    #   diagram = parser.parse("block-beta\n  columns 2\n  A\n  B")
    class Block < Base
      grammar Grammars::Block
      builder Builders::Block
    end
  end
end
