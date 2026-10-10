# frozen_string_literal: true

require "parslet"

module Sirena
  module Parser
    module Builders
      # Transform for Packet diagrams
      class Packet < Parslet::Transform
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
            label: label.is_a?(Array) ? "" : label.to_s,
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
          Array(statements).each do |stmt|
            next unless stmt.is_a?(Hash)

            case stmt[:type]
            when :title
              result[:title] = stmt[:title]
            else
              result[:fields] << stmt
            end
          end

          result
        end
      end
    end
  end
end
