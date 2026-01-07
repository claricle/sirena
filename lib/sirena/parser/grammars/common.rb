# frozen_string_literal: true

require 'parslet'

module Sirena
  module Parser
    module Grammars
      # Common grammar rules for Mermaid diagrams.
      #
      # Provides shared parsing patterns used across all diagram types,
      # including whitespace handling, comments, identifiers, strings,
      # and common punctuation.
      class Common < Parslet::Parser
        # Whitespace patterns
        rule(:space) { match[' \t'] }
        rule(:space?) { space.repeat }
        rule(:newline) { str("\n") | str("\r\n") }
        rule(:whitespace) { (space | newline).repeat(1) }
        rule(:whitespace?) { (space | newline).repeat }

        # Comments
        rule(:comment) { str('%%') >> (newline.absent? >> any).repeat }

        # Identifiers and keywords
        rule(:identifier) do
          match['a-zA-Z_'] >> match['a-zA-Z0-9_'].repeat
        end

        rule(:quoted_string) do
          str('"') >> (
            str('\\') >> any | str('"').absent? >> any
          ).repeat.as(:string) >> str('"')
        end

        rule(:single_quoted_string) do
          str("'") >> (
            str('\\') >> any | str("'").absent? >> any
          ).repeat.as(:string) >> str("'")
        end

        rule(:string) { quoted_string | single_quoted_string }

        # Numbers
        rule(:integer) { match['0-9'].repeat(1) }
        rule(:float) do
          integer >> str('.') >> integer
        end
        rule(:number) { float | integer }

        # Common punctuation
        rule(:colon) { str(':') }
        rule(:semicolon) { str(';') }
        rule(:comma) { str(',') }
        rule(:lparen) { str('(') }
        rule(:rparen) { str(')') }
        rule(:lbracket) { str('[') }
        rule(:rbracket) { str(']') }
        rule(:lbrace) { str('{') }
        rule(:rbrace) { str('}') }
        rule(:pipe) { str('|') }
        rule(:equals) { str('=') }
        rule(:plus) { str('+') }
        rule(:minus) { str('-') }
        rule(:asterisk) { str('*') }
        rule(:tilde) { str('~') }
        rule(:hash) { str('#') }

        # Line terminators
        rule(:line_end) do
          semicolon.maybe >> space? >> (comment.maybe >> newline | eof)
        end

        # Alias for end-of-line (used by some grammars)
        rule(:eol) { line_end }

        rule(:eof) { any.absent? }

        # Utility: skip whitespace and comments
        rule(:ws) { (space | newline | comment).repeat }
        rule(:ws?) { ws.maybe }
      end
    end
  end
end