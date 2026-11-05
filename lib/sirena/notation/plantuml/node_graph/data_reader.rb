# frozen_string_literal: true

require_relative "../../plantuml_data/boxes/json_reader"
require_relative "../../plantuml_data/boxes/highlights"
require_relative "../../plantuml_data/boxes/tree_builder"
require_relative "box_reader"
require_relative "edge"

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # What the node parser needs for a `json` element mixed into a use
        # case, component or deployment diagram, which PlantUML allows after
        # `allowmixing`. The element is drawn as the boxes of a JSON
        # diagram; a nested value is a box of its own, joined to its parent
        # by a dashed line. A `map` or `object` element is a box of its own,
        # read by {BoxReader}.
        module DataReader
          include BoxReader

          MIXING = /\Aallow_?mixing\z/i
          JSON_OPEN = /\Ajson\s+(?:"(?<label>[^"]+)"\s+as\s+)?
                       (?<id>\w[\w.]*)\s*\{(?<body>.*)\z/mx

          private

          def take_data(text)
            return unless @mixing

            take_json(text) || take_map(text) || take_object(text)
          end

          def take_json(text)
            return unless (match = text.match(JSON_OPEN))

            root = tree(json_text(match[:body]))
            data_node(match[:id], match[:label],
                      Boxes::Table.new(id: match[:id], title: root_title(match),
                                       rows: root.rows, kind: :inline))
          end

          def json_text(first)
            text = "{#{first}"
            while unbalanced?(text) && @index < @entries.size
              text += "\n#{@entries[@index].first}"
              @index += 1
            end
            text
          end

          def unbalanced?(text)
            text.count("{") > text.count("}")
          end

          def tree(text)
            value = PlantUMLData::Boxes::JsonReader.new.call(text)
            PlantUMLData::Boxes::TreeBuilder
              .new(PlantUMLData::Boxes::Highlights.new, inline: true)
              .call(value)
          end

          def root_title(match)
            match[:label] || match[:id]
          end

          def data_node(id, label, table)
            node = @graph.node(id, :data, parent: @stack.last)
            node.lines = [label || id]
            node.table = table
            node
          end
        end
      end
    end
  end
end
