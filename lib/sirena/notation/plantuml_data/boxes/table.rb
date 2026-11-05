# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUMLData
      # Shared model and drawing of PlantUML's box diagrams: JSON, YAML,
      # object and map diagrams all draw boxes of rows joined by links.
      module Boxes
        # One line of a {Table}. `key` is nil in an array or object body,
        # `child` the {Table} a link from this row ends at, `port` the name
        # an object diagram's `Map::port` reaches this row by and `style` a
        # highlight, or nil.
        Row = Data.define(:key, :value, :child, :port, :style) do
          def initialize(key: nil, value: "", child: nil, port: nil,
                         style: nil)
            super
          end
        end

        # A box. `kind` is :tree for JSON and YAML, :object or :map; `group`
        # names the packages around it, outermost first (the JAR makes a
        # dotted object name `a.b.c` a box `a.b.c` inside packages `a` and
        # `b`).
        Table = Data.define(:id, :title, :rows, :kind, :group) do
          def initialize(rows:, id: nil, title: nil, kind: :tree, group: [])
            super
          end

          def keyed?
            rows.any?(&:key)
          end
        end

        # A line between two tables. `from_row` is the Row it leaves, or nil
        # for a table-to-table relation. `glyph` is an Arrow.parse result.
        # `label` runs along the line; `tail_text` and `head_text` are the
        # quoted texts beside its two ends.
        Link = Data.define(:from, :to, :from_row, :to_row, :glyph, :label,
                           :tail_text, :head_text) do
          def initialize(from:, to:, glyph:, from_row: nil, to_row: nil,
                         label: nil, tail_text: nil, head_text: nil)
            super
          end
        end

        # A parsed diagram. `roots` are the tables laid out first.
        Diagram = Data.define(:tables, :links, :title, :direction) do
          def initialize(tables:, links: [], title: nil, direction: :down)
            super
          end
        end
      end
    end
  end
end
