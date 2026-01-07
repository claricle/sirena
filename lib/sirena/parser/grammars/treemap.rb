# frozen_string_literal: true

require 'parslet'

module Sirena
  module Parser
    module Grammars
      # Parslet grammar for treemap diagrams
      class Treemap < Parslet::Parser
        rule(:space) { match[' \t'] }
        rule(:space?) { space.maybe }
        rule(:spaces) { space.repeat(1) }
        rule(:spaces?) { space.repeat }
        rule(:newline) { str("\n") | str("\r\n") }
        rule(:newlines) { newline.repeat(1) }
        rule(:newlines?) { newline.repeat }
        rule(:eof) { any.absent? }

        # Comments
        rule(:comment) { str('%%') >> (newline.absent? >> any).repeat }

        # Numbers
        rule(:number) do
          (match['-'].maybe >> match['0-9'].repeat(1) >>
           (str('.') >> match['0-9'].repeat(1)).maybe).as(:number)
        end

        # Quoted strings
        rule(:quoted_string) do
          str('"') >> (
            str('\\') >> any |
            str('"').absent? >> any
          ).repeat.as(:string) >> str('"')
        end

        # Identifiers
        rule(:identifier) do
          (match['a-zA-Z_'] >> match['a-zA-Z0-9_-'].repeat).as(:identifier)
        end

        # Keywords
        rule(:treemap_keyword) do
          (str('treemap-beta') | str('treemap')).as(:keyword)
        end

        # Title declaration
        rule(:title_decl) do
          str('title') >> spaces >> (newline.absent? >> any).repeat(1).as(:title)
        end

        # Accessibility declarations
        rule(:acc_title) do
          str('accTitle:') >> spaces? >> (newline.absent? >> any).repeat(1).as(:acc_title)
        end

        rule(:acc_descr) do
          str('accDescr') >> spaces? >> str(':').maybe >> spaces? >>
            (newline.absent? >> any).repeat(1).as(:acc_descr)
        end

        # CSS class reference
        rule(:css_class) do
          str(':::') >> identifier.as(:css_class)
        end

        # Value separator (: or ,) with optional spaces before and after
        rule(:value_separator) { spaces? >> (str(':') | str(',')) >> spaces? }

        # Node with optional value and CSS class
        rule(:node_value) do
          quoted_string.as(:label) >>
            (value_separator >> number.as(:value)).maybe >>
            css_class.maybe
        end

        # Capture leading spaces as a string to count indentation
        rule(:indent_str) do
          match[' '].repeat.as(:indent)
        end

        # Node line (with indentation captured)
        rule(:node_line) do
          indent_str >> node_value >> spaces? >>
            (comment.maybe >> (newline | eof))
        end

        # Class definition
        rule(:class_def) do
          str('classDef') >> spaces >>
            identifier.as(:class_name) >> spaces >>
            (str(';').absent? >> any).repeat(1).as(:class_styles) >>
            str(';').maybe
        end

        # Statement (title, acc, node, or class def)
        rule(:statement) do
          (
            title_decl >> spaces? |
            acc_title >> spaces? |
            acc_descr >> spaces? |
            class_def.as(:class_def) >> spaces? |
            node_line.as(:node) |
            comment >> spaces? |
            spaces? >> newline
          )
        end

        # Main diagram
        rule(:diagram) do
          treemap_keyword >>
            spaces? >> newline >>
            statement.repeat.as(:statements) >>
            spaces? >> eof
        end

        root(:diagram)
      end
    end
  end
end