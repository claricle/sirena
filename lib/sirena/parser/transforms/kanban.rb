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
            # mermaid renders. Resolved here, once: add_card reads this field
            # directly, and add_column reads it through column_title, which
            # may override it with a `label:` from the metadata.
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
          # is what mermaid renders. A label mermaid would treat as unset is
          # already gone by here - parse_metadata drops it - so the fallback
          # to the bracket text, or to the id, is a plain `||`.
          #
          # On a CARD the label is instead kept as its own attribute and drawn
          # as a separate "Label:" row. That DIVERGES FROM MERMAID, which
          # renders the label as the card's primary text and draws no such
          # row. The divergence is pre-existing and unchanged here; correcting
          # it belongs to the card-conformance bucket.
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
              next if dropped_by_mermaid?(entry[:value])

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

            if value_data.is_a?(Hash)
              # An empty quoted string parses as `{string: []}`, because the
              # shared grammar captures the body with `.repeat`. `[].to_s` is
              # the literal "[]", so join the capture instead of stringifying
              # it.
              Array(value_data[:string] || value_data[:unquoted]).join
            else
              value_data.to_s
            end
          end

          # Mermaid gates every metadata field on JS truthiness - the kanban
          # renderer reads `if (doc?.label)`, and icon, assigned, ticket and
          # priority the same way - AFTER js-yaml has resolved the scalar. A
          # value resolving to false, null or numeric zero is therefore never
          # set, and the field falls back as though it were absent. Dropping
          # the entry here mirrors that: mermaid has no entry either, so it
          # draws no metadata row and reserves no height for one.
          #
          # Only UNQUOTED values are resolved. A quoted value stays a string,
          # and a non-empty string is truthy, so `'0'` and `"false"` override
          # while `''` and `""` do not.
          #
          # Only the FALSY half of js-yaml resolution is mirrored here. A
          # scalar that resolves to a truthy value is still rendered as its
          # raw text, where mermaid renders the resolved value - it draws `1`
          # for `1e0`, `7` for `007` and `16` for `0x10`, and we draw the
          # input verbatim. That divergence is pre-existing, it is not
          # narrowed or widened by this bucket, and it belongs with the
          # card-conformance work. Do not read this method as "we match
          # mermaid on unquoted scalars".
          #
          # None of this has any corpus exposure: every `@{...}` value in all
          # 1997 cases is a truthy string. It is pinned by the specs and by
          # mmdc probes, never by the sweep - "16 fixed" is not evidence for
          # any of it.
          def dropped_by_mermaid?(value_data)
            text = extract_value(value_data)
            return true if text.empty?
            return false unless value_data.is_a?(Hash) && value_data.key?(:unquoted)

            YAML_FALSE_WORDS.include?(text) || yaml_zero?(text)
          end

          # js-yaml resolves these spellings, and only these, to false or
          # null. `True`/`TRUE` resolve to boolean true and stay truthy, and
          # `no`, `off`, `n` and `y` are plain strings here.
          YAML_FALSE_WORDS = %w[false False FALSE null Null NULL].freeze
          private_constant :YAML_FALSE_WORDS

          # Spellings js-yaml resolves as a number, measured against mmdc
          # 11.12.0 rather than recalled. Case matters where you would not
          # expect it: the radix prefix is lowercase-only, so `0x0` and `0o0`
          # resolve to zero while `0X0` and `0O0` stay strings, but the
          # exponent marker is case-insensitive and `0e0` and `0E0` both do.
          #
          # `_` is a digit separator. A run of any length counts, and one may
          # follow a radix prefix - `0_0`, `0__0`, `0___0`, `00__00` and
          # `0x_0` all resolve - but it may never lead, so `_0`, `__0` and
          # `-_0` stay strings. It cannot bridge into a prefix either:
          # `0_x0` is a string.
          #
          # Whether a TRAILING separator is allowed depends on the resolver
          # mermaid reaches, so the two branches genuinely differ and must
          # not be unified. The int pattern rejects one, so `0_` and `0_0_`
          # stay strings; the float pattern is `[0-9][0-9_]*`, which accepts
          # one, so a mantissa may end in separators and `0_e0`, `0__e0` and
          # `0_0_e0` all resolve. The exponent takes no separators at all,
          # which is why `0e0_0` and `0_e_0` stay strings.
          #
          # This covers what the grammar can actually produce - unquoted_value
          # is `match['a-zA-Z0-9_\-']`, so `0.0`, `~` and `.nan` cannot reach
          # here even though mermaid treats them as falsy too. That is a
          # separate pre-existing gap in the charset, not fixed in this
          # bucket. Widen the charset and these cases need re-probing, not
          # guessing.
          YAML_DECIMAL = /\A-?\d+(?:_+\d+)*\z/
          YAML_HEX = /\A-?0x_*[0-9a-f]+(?:_+[0-9a-f]+)*\z/
          YAML_OCTAL = /\A-?0o_*[0-7]+(?:_+[0-7]+)*\z/
          YAML_BINARY = /\A-?0b_*[01]+(?:_+[01]+)*\z/
          YAML_EXPONENT = /\A-?\d[\d_]*[eE][-+]?\d+\z/
          private_constant :YAML_DECIMAL, :YAML_HEX, :YAML_OCTAL,
                           :YAML_BINARY, :YAML_EXPONENT

          def yaml_zero?(text)
            digits = text.delete('_')

            case text
            when YAML_DECIMAL then digits.to_i.zero?
            when YAML_HEX then digits[/0x(.+)/, 1].to_i(16).zero?
            when YAML_OCTAL then digits[/0o(.+)/, 1].to_i(8).zero?
            when YAML_BINARY then digits[/0b(.+)/, 1].to_i(2).zero?
            when YAML_EXPONENT then digits.to_f.zero?
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