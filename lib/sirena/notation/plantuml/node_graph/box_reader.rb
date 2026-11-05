# frozen_string_literal: true

require_relative "../objects/map_rows"
require_relative "../../plantuml_data/boxes/table"
require_relative "link"

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # What the node parser needs for a `map` or `object` element mixed
        # into a use case, component or deployment diagram after
        # `allowmixing`. The element is drawn as the box an object diagram
        # draws, and a link may start or end at one of its rows
        # (`Element::key`).
        module BoxReader
          Boxes = PlantUMLData::Boxes
          NAME = /(?:"(?<label>[^"]+)"\s+as\s+)?(?<id>\w[\w.]*)/
          MAP_OPEN = /\Amap\s+#{NAME}\s*\{\z/
          OBJECT_OPEN = /\Aobject\s+#{NAME}(?:\s*(?<open>\{))?\z/
          FIELD = /\A[[:alpha:]_][[:alnum:]_]*/

          private

          def take_map(text)
            return unless (match = text.match(MAP_OPEN))

            rows, links = Objects::MapRows.call(body_lines)
            node = box_node(match, :map, rows)
            links.each { |link| row_edge(node, *link) }
            node
          end

          def take_object(text)
            return unless (match = text.match(OBJECT_OPEN))

            rows = match[:open] ? body_lines.map { |line| field(line) } : []
            box_node(match, :object, rows)
          end

          def field(line)
            Boxes::Row.new(value: line, port: line[FIELD])
          end

          def body_lines
            lines = []
            while (entry = @entries[@index])
              @index += 1
              return lines if entry.first == "}"

              lines << entry.first
            end
            raise Sirena::Parser::ParseError,
                  "Parse error: unclosed { at line #{@number}"
          end

          def box_node(match, kind, rows)
            title = match[:label] || match[:id]
            data_node(match[:id], match[:label],
                      Boxes::Table.new(id: match[:id], title: title, rows: rows,
                                       kind: kind))
          end

          # The edge a `key *-> target` row of `node` stands for.
          def row_edge(node, key, arrow, target)
            name, port = target.split("::")
            to = resolve(name)
            @graph.edges << Link.new(arrow).edge(
              node, to, from_row: row_index(node, key),
                        to_row: row_index(to, port)
            )
          end

          # @return [Integer, nil] the row of a map or object box that
          #   `port` names; any other box has no rows to end a line at
          def row_index(node, port)
            table = node.table
            return unless port && %i[map object].include?(table&.kind)

            table.rows.index { |row| row.port == port }
          end
        end
      end
    end
  end
end
