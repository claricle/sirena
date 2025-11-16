# frozen_string_literal: true

require_relative 'common'

module Sirena
  module Parser
    module Grammars
      # Parslet grammar for Block diagrams.
      #
      # Handles block diagram syntax including column layout, blocks with
      # various shapes, compound blocks, connections, and styling.
      class Block < Common
        root(:diagram)

        # Main diagram structure
        rule(:diagram) do
          ws? >>
            header >>
            ws? >>
            statements.maybe >>
            ws?
        end

        rule(:header) do
          str('block-beta').as(:header) >> ws?
        end

        rule(:statements) do
          (statement >> ws?).repeat(1)
        end

        rule(:statement) do
          columns_statement |
            style_statement |
            connection_statement |
            compound_block_statement |
            block_statement
        end

        # Columns: columns N
        rule(:columns_statement) do
          str('columns').as(:columns_keyword) >> space >>
            integer.as(:columns_value) >>
            line_end
        end

        # Compound block: block:ID ... end or block ... end
        rule(:compound_block_statement) do
          str('block').as(:compound_keyword) >>
            (colon >> block_id.as(:compound_id)).maybe >>
            space? >>
            line_end >>
            ws? >>
            compound_statements.maybe.as(:compound_statements) >>
            ws? >>
            str('end').as(:compound_end) >>
            line_end
        end

        rule(:compound_statements) do
          (compound_statement >> ws?).repeat(1)
        end

        rule(:compound_statement) do
          compound_block_statement |
            block_statement
        end

        # Style: style blockId fill:#f9f,stroke:#333
        rule(:style_statement) do
          str('style').as(:style_keyword) >> space >>
            block_id.as(:style_target) >>
            space >>
            style_properties.as(:style_props) >>
            line_end
        end

        rule(:style_properties) do
          style_property >> (comma >> style_property).repeat
        end

        rule(:style_property) do
          (line_end.absent? >> comma.absent? >> any).repeat(1)
        end

        # Connection: A --> B or A --- B
        rule(:connection_statement) do
          block_id.as(:from) >>
            space? >>
            arrow.as(:arrow) >>
            space? >>
            block_id.as(:to) >>
            line_end
        end

        rule(:arrow) do
          str('-->').as(:arrow_type) |
            str('---').as(:line_type)
        end

        # Block statement: can be space, simple block, or block with shape/width
        rule(:block_statement) do
          space_block |
            arrow_block |
            block_with_shape
        end

        # Space placeholder
        rule(:space_block) do
          str('space').as(:space_keyword) >> line_end
        end

        # Arrow block: blockArrowId<["&nbsp;"]>(down)
        rule(:arrow_block) do
          block_id.as(:arrow_id) >>
            str('<').as(:arrow_open) >>
            lbracket >>
            (rbracket.absent? >> any).repeat.as(:arrow_label) >>
            rbracket >>
            str('>').as(:arrow_close) >>
            lparen >>
            arrow_direction.as(:arrow_direction) >>
            rparen >>
            line_end
        end

        rule(:arrow_direction) do
          (str('up') | str('down') | str('left') | str('right')).as(:direction)
        end

        # Block with optional shape and width
        rule(:block_with_shape) do
          block_id.as(:block_id) >>
            (space? >> block_shape.as(:block_shape)).maybe >>
            (block_width.as(:block_width)).maybe >>
            line_end
        end

        # Block width: :N
        rule(:block_width) do
          colon >> integer
        end

        # Block shapes
        rule(:block_shape) do
          shape_double_circle |
            shape_rectangle
        end

        # Rectangle shape: ["label"]
        rule(:shape_rectangle) do
          lbracket.as(:open) >>
            (rbracket.absent? >> any).repeat.as(:label) >>
            rbracket.as(:close)
        end

        # Circle shape: (("label"))
        rule(:shape_double_circle) do
          str('((').as(:open) >>
            (str('))').absent? >> any).repeat.as(:label) >>
            str('))').as(:close)
        end

        # Block identifier - can be quoted string or identifier
        # but not reserved keywords when standalone
        rule(:block_id) do
          quoted_string |
            (reserved_keyword.absent? >> identifier)
        end

        # Reserved keywords that can't be used as standalone block IDs
        # Only keywords that would be ambiguous in block_statement context
        rule(:reserved_keyword) do
          (str('block') | str('end') | str('space')) >>
            (identifier_char.absent?)
        end

        # Identifier character (for lookahead)
        rule(:identifier_char) do
          match['a-zA-Z0-9_']
        end

        # Line terminator
        rule(:line_end) do
          semicolon.maybe >> space? >> (comment.maybe >> newline | eof)
        end
      end
    end
  end
end