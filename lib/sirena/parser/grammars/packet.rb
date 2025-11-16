# frozen_string_literal: true

require "parslet"
require_relative "common"

module Sirena
  module Parser
    module Grammars
      # Grammar for parsing Mermaid packet-beta diagram syntax
      class Packet < Common

        rule(:diagram_type) { str("packet-beta") >> space? }

        rule(:text) { match['^\n'].repeat(1) }

        rule(:title_line) do
          str("title") >> space >> text.as(:title) >> newline
        end

        # Field definition: 0-10: "Label"
        rule(:bit_number) do
          match["0-9"].repeat(1)
        end

        rule(:bit_range) do
          bit_number.as(:bit_start) >>
            str("-") >>
            bit_number.as(:bit_end)
        end

        rule(:field_label) do
          str('"') >>
            match('[^"]').repeat(0).as(:label) >>
            str('"')
        end

        rule(:field_line) do
          bit_range >>
            str(":") >> space? >>
            field_label >>
            (newline | eof)
        end

        rule(:comment_line) do
          comment >> newline
        end

        rule(:empty_line) do
          space? >> newline
        end

        rule(:indent?) { space? }

        rule(:statement) do
          indent? >> (
            title_line |
            field_line |
            comment_line |
            empty_line
          )
        end

        rule(:body) { statement.repeat(0) }

        rule(:packet_diagram) do
          diagram_type >> (newline >> body.as(:statements)).maybe >> eof.maybe
        end

        root(:packet_diagram)
      end
    end
  end
end