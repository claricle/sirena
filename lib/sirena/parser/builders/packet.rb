# frozen_string_literal: true

require "parslet"

module Sirena
  module Parser
    module Builders
      # Transform for Packet diagrams
      class Packet < Parslet::Transform
        LABEL_TEXT = lambda do |captured|
          captured.is_a?(Array) ? "" : captured.to_s.gsub(/\\(.)/m, '\\1')
        end
        private_constant :LABEL_TEXT

        # Transform field definition. label is `subtree`, not `simple`,
        # because an empty quoted label ("") captures zero characters --
        # Parslet's `.repeat(0).as(:label)` has no bytes to build a Slice
        # from on a zero-length match, so it yields `[]` instead of an
        # empty Slice. `simple(:label)` refuses to bind an Array, which
        # silently dropped the whole field (no :type key survived, so the
        # diagram-level rule below skipped it without error).
        rule(
          bit_start: simple(:bit_start),
          bit_end: simple(:bit_end),
          label: subtree(:label),
        ) do
          {
            type: :field,
            bit_start: bit_start.to_s.to_i,
            bit_end: bit_end.to_s.to_i,
            label: LABEL_TEXT.call(label),
          }
        end

        rule(
          bit_start: simple(:bit_start),
          label: subtree(:label),
        ) do
          bit = bit_start.to_s.to_i
          {
            type: :field,
            bit_start: bit,
            bit_end: bit,
            label: LABEL_TEXT.call(label),
          }
        end

        # Transform title
        rule(title: simple(:title)) do
          { type: :title, title: title.to_s }
        end

        # Transform the entire diagram
        rule(statements: subtree(:statements)) do
          result = {
            title: nil,
            fields: [],
          }

          # A body of only comments and blank lines parses to one string,
          # not an Array of statements.
          expected_start = 0
          Array(statements).each do |stmt|
            next unless stmt.is_a?(Hash)

            case stmt[:type]
            when :title
              result[:title] = stmt[:title]
            else
              if stmt[:bit_end] < stmt[:bit_start]
                raise Parser::ParseError,
                      "Packet field end must be greater than or equal to start."
              end
              unless stmt[:bit_start] == expected_start
                raise Parser::ParseError,
                      "Packet fields must start from #{expected_start}."
              end
              result[:fields] << stmt
              expected_start = stmt[:bit_end] + 1
            end
          end

          result
        end
      end
    end
  end
end
