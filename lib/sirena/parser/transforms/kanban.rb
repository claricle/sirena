# frozen_string_literal: true

require "parslet"

module Sirena
  module Parser
    module Transforms
      # Transform for Kanban diagrams
      class Kanban < Parslet::Transform
        # Helper class to build kanban board from indented lines
        class BoardBuilder
          # js-yaml resolves these spellings, and only these, to false or
          # null. `True`/`TRUE` resolve to boolean true and stay truthy;
          # `no`, `off`, `n` and `y` are plain strings here.
          YAML_FALSY_WORDS = %w[false False FALSE null Null NULL].freeze
          private_constant :YAML_FALSY_WORDS

          # Spellings js-yaml resolves as a number. Case matters unevenly:
          # the radix prefix is lowercase-only, so `0x0` and `0o0` resolve
          # while `0X0` and `0O0` stay strings, but the exponent marker is
          # case-insensitive and `0e0` and `0E0` both resolve.
          #
          # `_` is a digit separator. A run of any length counts and one may
          # follow a radix prefix (`0_0`, `0__0`, `0x_0`), but it may never
          # lead (`_0`, `__0`, `-_0`) and cannot bridge into a prefix
          # (`0_x0`). Int and float disagree about a TRAILING separator, so
          # they stay separate patterns: the int resolver rejects one, so
          # `0_` and `0_0_` stay strings, while the float mantissa is
          # `[0-9][0-9_]*` and accepts one, so `0_e0` resolves. The exponent
          # itself takes no separators, so `0e0_0` and `0_e_0` stay strings.
          #
          # `0.0`, `~` and `.nan` are falsy to mermaid but cannot reach here:
          # unquoted_value admits neither `.` nor `~`. Widening that charset
          # means re-probing these patterns.
          YAML_DECIMAL = /\A-?\d+(?:_+\d+)*\z/
          YAML_HEX = /\A-?0x_*[0-9a-f]+(?:_+[0-9a-f]+)*\z/
          YAML_OCTAL = /\A-?0o_*[0-7]+(?:_+[0-7]+)*\z/
          YAML_BINARY = /\A-?0b_*[01]+(?:_+[01]+)*\z/
          YAML_FLOAT = /\A-?\d[\d_]*[eE][-+]?\d+\z/
          private_constant :YAML_DECIMAL, :YAML_HEX, :YAML_OCTAL,
                           :YAML_BINARY, :YAML_FLOAT
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

          def extract_value(value_data)
            return "" if value_data.nil?

            if value_data.is_a?(Hash)
              # An empty quoted string captures as `{string: []}`, because
              # the shared grammar takes the body with `.repeat`, and
              # `[].to_s` is the literal "[]". Parslet::Slice answers false
              # to `to_ary`, so `Array()` wraps a slice rather than splitting
              # it; `join` then handles both shapes.
              Array(value_data[:string] || value_data[:unquoted]).join
            else
              value_data.to_s
            end
          end

          # Mermaid gates every field on JS truthiness - the kanban renderer
          # reads `if (doc?.label)`, and icon, assigned, ticket and priority
          # the same way - AFTER js-yaml resolves the scalar. A value
          # resolving to false, null or zero is therefore never set and the
          # field falls back. Dropping the entry mirrors that: with no entry
          # there is no metadata row and no height reserved for one.
          #
          # An empty value is dropped whatever its quoting. Past that, only
          # UNQUOTED values are resolved: a non-empty quoted string is always
          # truthy, so `'0'` and `"false"` override.
          #
          # Only the falsy half of resolution is mirrored. A truthy scalar is
          # still rendered as its raw text where mermaid renders the resolved
          # value - `1e0` draws `1`, `0x10` draws `16`. That divergence is
          # pre-existing and belongs to the card-conformance bucket.
          def dropped_by_mermaid?(text, unquoted:)
            return true if text.empty?
            return false unless unquoted

            YAML_FALSY_WORDS.include?(text) || yaml_zero?(text)
          end

          def yaml_zero?(text)
            case text
            when YAML_DECIMAL then digits_of(text).to_i.zero?
            when YAML_HEX then digits_of(text)[/0x(.+)/, 1].to_i(16).zero?
            when YAML_OCTAL then digits_of(text)[/0o(.+)/, 1].to_i(8).zero?
            when YAML_BINARY then digits_of(text)[/0b(.+)/, 1].to_i(2).zero?
            when YAML_FLOAT then digits_of(text).to_f.zero?
            else false
            end
          end

          # The patterns above have already vetted where a separator may sit,
          # so they can be dropped before conversion.
          def digits_of(text)
            text.delete('_')
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