# frozen_string_literal: true

require "parslet"

module Sirena
  module Parser
    module Transforms
      # Transform for Kanban diagrams
      class Kanban < Parslet::Transform
        # Helper class to build kanban board from indented lines
        class BoardBuilder
          attr_reader :columns

          def initialize
            @columns = []
            @current_column = nil
            @min_indent = nil
            @items = []
          end

          def add_line(line_data)
            # Skip empty lines
            return if line_data.nil?
            return unless line_data[:id]

            indent_size = get_indent_size(line_data[:indent])

            # Track minimum indentation
            @min_indent = indent_size if @min_indent.nil? || indent_size < @min_indent

            id = line_data[:id].to_s

            # An item with no bracket label displays its id, which is what
            # mermaid renders. Resolved here, once, because add_column and
            # add_card both read this same field.
            #
            # The metadata is parsed here rather than in add_card so that
            # add_column can consult it too; parse_metadata returns {} for a
            # nil subtree, so this is always a Hash.
            @items << {
              id: id,
              text: line_data[:text]&.to_s || id,
              indent: indent_size,
              metadata: parse_metadata(line_data[:metadata])
            }
          end

          def finalize
            return if @items.empty?

            # Determine column vs card by indentation
            # Items at minimum indent are columns, items with more indent are cards
            @items.each do |item|
              if item[:indent] == @min_indent
                # This is a column
                add_column(item)
              else
                # This is a card, add to current column
                add_card(item)
              end
            end
          end

          private

          def add_column(item)
            column = {
              id: item[:id],
              title: column_title(item),
              cards: []
            }

            @columns << column
            @current_column = column
          end

          def add_card(item)
            # Cards must belong to a column
            return unless @current_column

            # `id` and `text` are the card's own fields, not metadata keys.
            # Mermaid ignores an `@{ id: ... }` or `@{ text: ... }` entry, so
            # the merge must not let one overwrite them.
            @current_column[:cards] << {
              id: item[:id],
              text: item[:text]
            }.merge(item[:metadata].except(:id, :text))
          end

          # A `label:` in the metadata replaces a COLUMN's display text, which
          # is what mermaid renders. An empty label is not a label: it falls
          # back to the bracket text, or to the id when there is no bracket
          # text. On a CARD the label is kept as its own attribute and drawn
          # as a separate "Label:" row, which this bucket leaves untouched.
          def column_title(item)
            label = item[:metadata][:label]
            label.nil? || label.empty? ? item[:text] : label
          end

          def parse_metadata(metadata_data)
            return {} if metadata_data.nil?

            result = {}

            # metadata_data could be a single entry or an array
            entries = if metadata_data.is_a?(Array)
                       metadata_data
                     else
                       [metadata_data]
                     end

            entries.each do |entry|
              next unless entry.is_a?(Hash)
              next unless entry[:key] && entry[:value]

              key = entry[:key].to_s
              value = extract_value(entry[:value])

              # Map to known metadata fields
              case key
              when "assigned"
                result[:assigned] = value
              when "ticket"
                result[:ticket] = value
              when "icon"
                result[:icon] = value
              when "label"
                result[:label] = value
              when "priority"
                result[:priority] = value
              else
                # Store unknown keys as-is
                result[key.to_sym] = value
              end
            end

            result
          end

          def extract_value(value_data)
            return "" if value_data.nil?

            if value_data.is_a?(Hash) && value_data.key?(:string)
              # An empty quoted string parses as `{string: []}`, because the
              # shared grammar captures the body with `.repeat`. `[].to_s` is
              # the literal "[]", so join the capture instead of stringifying
              # it.
              Array(value_data[:string]).join
            else
              value_data.to_s
            end
          end

          def get_indent_size(indent_data)
            return 0 if indent_data.nil?
            return 0 if indent_data.is_a?(Array) && indent_data.empty?

            indent_str = if indent_data.is_a?(Array)
                          indent_data.join('')
                        else
                          indent_data.to_s
                        end

            indent_str.length
          end
        end

        # Transform the lines array into columns and cards
        rule(lines: subtree(:lines)) do
          builder = BoardBuilder.new
          lines_array = Array(lines)

          lines_array.each do |line_data|
            next unless line_data.is_a?(Hash)

            # Skip empty lines
            next unless line_data[:id]

            builder.add_line(line_data)
          end

          builder.finalize

          {
            columns: builder.columns
          }
        end
      end
    end
  end
end