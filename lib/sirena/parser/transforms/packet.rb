# frozen_string_literal: true

require "parslet"

module Sirena
  module Parser
    module Transforms
      # Transform for Packet diagrams
      class Packet < Parslet::Transform
        # Transform field definition
        rule(
          bit_start: simple(:bit_start),
          bit_end: simple(:bit_end),
          label: simple(:label)
        ) do
          {
            type: :field,
            bit_start: bit_start.to_s.to_i,
            bit_end: bit_end.to_s.to_i,
            label: label.to_s
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
            fields: []
          }

          # Handle nil or empty statements
          stmts = statements.nil? ? [] : Array(statements)

          stmts.each do |stmt|
            next unless stmt.is_a?(Hash)

            case stmt[:type]
            when :title
              result[:title] = stmt[:title]
            when :field
              result[:fields] << stmt
            end
          end

          result
        end

        # Handle empty diagram (no statements)
        rule(statements: nil) do
          {
            title: nil,
            fields: []
          }
        end
      end
    end
  end
end