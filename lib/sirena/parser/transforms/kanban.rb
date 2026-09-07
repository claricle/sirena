# frozen_string_literal: true

require "parslet"

require_relative "../metadata_yaml"

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
            # mermaid renders. Resolved here, once: add_card reads this field
            # directly, and add_column reads it through column_title, which
            # may override it with a `label:` from the metadata.
            #
            # The metadata is parsed here rather than in add_card so that
            # add_column can consult it too; parse_metadata returns {} for a
            # nil subtree, so this is always a Hash.
            #
            # `|| id` relies on an absent label being nil rather than "",
            # since `""` is truthy in Ruby and would not fall back. That
            # holds only because labelled_item captures with `repeat(1)`, so
            # a label that matched is never empty.
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

          # The card's own `id` and `text` beat a metadata entry of the same
          # name, because mermaid ignores `@{ id: ... }` and `@{ text: ... }`.
          # Merging the metadata FIRST makes that true by construction, with
          # no exclusion list to keep in step as fields are added.
          #
          # A `label:` on a card is kept as its own attribute and drawn as a
          # separate "Label:" row. That diverges from mermaid, which renders
          # the label as the card's primary text and draws no such row. The
          # divergence is pre-existing; correcting it belongs to the
          # card-conformance bucket.
          def add_card(item)
            # Cards must belong to a column
            return unless @current_column

            @current_column[:cards] << item[:metadata].merge(
              id: item[:id],
              text: item[:text]
            )
          end

          # A `label:` replaces a COLUMN's display text, which is what mermaid
          # renders. A label mermaid would treat as unset is already gone by
          # here - parse_metadata drops it - so falling back to the bracket
          # text, or to the id, is a plain `||`.
          def column_title(item)
            item[:metadata][:label] || item[:text]
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

              value = extract_value(entry[:value])
              next if dropped_by_mermaid?(value, unquoted: entry[:value].key?(:unquoted))

              key = entry[:key].to_s

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

          # Always a Hash of `{string: ...}` or `{unquoted: ...}`: every branch
          # of `metadata_value` captures with `.as(:string)` or `.as(:unquoted)`,
          # and the caller has already skipped a nil value. So no guard here.
          #
          # An empty quoted string captures as `{string: []}`, because the
          # shared grammar takes the body with `.repeat`, and `[].to_s` is the
          # literal "[]". Parslet::Slice answers false to `to_ary`, so
          # `Array()` wraps a slice rather than splitting it; `join` then
          # handles both shapes.
          def extract_value(value_data)
            Array(value_data[:string] || value_data[:unquoted]).join
          end

          # Mermaid gates every field on JS truthiness - the kanban renderer
          # reads `if (doc?.label)`, and icon, assigned, ticket and priority
          # the same way - AFTER js-yaml resolves the scalar. A value
          # resolving to false, null or zero is therefore never set and the
          # field falls back. Dropping the entry mirrors that: with no entry
          # there is no metadata row and no height reserved for one.
          #
          # An empty value is dropped. Only a QUOTED one can be empty -
          # `unquoted_value` captures with `repeat(1)` - so that rule and the
          # unquoted resolution below never both apply. Past it, a non-empty
          # quoted string is always truthy, so `'0'` and `"false"` override.
          #
          # Only the falsy half of resolution is mirrored. A truthy scalar is
          # still rendered as its raw text where mermaid renders the resolved
          # value - `1e0` draws `1`, `0x10` draws `16`. That divergence is
          # pre-existing and belongs to the card-conformance bucket.
          #
          # The resolution itself is MetadataYaml's, the same table the
          # flowchart body is read with. `no`, `off`, `True` and `0_1` stay
          # truthy there, and `false`, `null`, `~`, `.nan` and every zero
          # resolve falsy, which is what mermaid's js-yaml 4.1.1 does.
          def dropped_by_mermaid?(text, unquoted:)
            return true if text.empty?
            return false unless unquoted

            falsy_to_js?(MetadataYaml.plain_scalar(text))
          end

          # JavaScript's own falsy set, over the values js-yaml can hand
          # back for a plain scalar: false, null, any zero and NaN. An empty
          # string is already gone above, and a non-empty one is truthy.
          def falsy_to_js?(value)
            case value
            when nil, false then true
            when Float then value.zero? || value.nan?
            when Numeric then value.zero?
            else false
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