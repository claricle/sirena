# frozen_string_literal: true

require_relative "table"
require_relative "text"

module Sirena
  module Notation
    module PlantUMLData
      module Boxes
        # Turns a parsed JSON or YAML value into {Table}s: a hash is a box of
        # key and value rows, an array a box of value rows, and a nested hash
        # or array a box of its own that the row links to.
        class TreeBuilder
          Entry = Data.define(:key, :segment, :item)
          private_constant :Entry

          # @param highlights [#style_for] answers the style of a key path
          # @param inline [Boolean] a nested value fills its row's cell
          #   instead of being a box of its own
          def initialize(highlights, inline: false)
            @highlights = highlights
            @inline = inline
          end

          # @return [Table] the root; its descendants hang off its rows
          def call(value)
            build(value, [])
          end

          private

          def build(value, path)
            Table.new(rows: entries(value).map { |entry| row(entry, path) })
          end

          def entries(value)
            case value
            when Hash then value.map { |k, v| keyed(k, v) }
            when Array then value.each_with_index.map { |v, i| indexed(i, v) }
            else [Entry.new(key: nil, segment: "", item: value)]
            end
          end

          def keyed(key, item)
            Entry.new(key: key.to_s, segment: key.to_s, item: item)
          end

          def indexed(index, item)
            Entry.new(key: nil, segment: index.to_s, item: item)
          end

          def row(entry, path)
            here = path + [entry.segment]
            style = @highlights.style_for(here)
            item = entry.item
            return plain_row(entry, style) unless container?(item)

            nested = build(item, here)
            return inline_row(entry, style, nested) if @inline

            Row.new(key: entry.key, value: Text::BLANK, style: style,
                    child: nested)
          end

          def inline_row(entry, style, nested)
            Row.new(key: entry.key, style: style,
                    inline: (nested unless nested.rows.empty?))
          end

          def plain_row(entry, style)
            value = @inline ? Text.literal(entry.item) : Text.scalar(entry.item)
            Row.new(key: entry.key, value: value, style: style)
          end

          def container?(item)
            item.is_a?(Hash) || item.is_a?(Array)
          end
        end
      end
    end
  end
end
