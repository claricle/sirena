# frozen_string_literal: true

require_relative "../../plantuml_data/boxes/table"

module Sirena
  module Notation
    module PlantUML
      module Objects
        # Reads the lines inside a PlantUML `map` element: `key => value`
        # rows, bare keys, and `key *-> target` rows that link out.
        module MapRows
          extend self

          NAME = /[A-Za-z_][A-Za-z0-9_.]*/
          VALUE = /\A(.+?)[ \t]*=>[ \t]*(.*)\z/
          LINK = /\A(.+?)[ \t]+(\*?-+>)[ \t]*(#{NAME}(?:::#{NAME})?)\z/o
          private_constant :VALUE, :LINK

          # @param lines [Array<String>] the stripped lines of the body
          # @return [Array(Array<Boxes::Row>, Array<Array(String, String,
          #   String)>)] the rows and the key, arrow and target of each link
          def call(lines)
            links = []
            rows = lines.map { |line| row(line, links) }
            [rows, links]
          end

          private

          def row(line, links)
            if (found = LINK.match(line))
              key, glyph, target = found.captures
              links << [key, glyph, target]
              PlantUMLData::Boxes::Row.new(key: key, port: key)
            else
              pair = VALUE.match(line)
              PlantUMLData::Boxes::Row.new(key: pair ? pair[1] : line,
                                           port: pair ? pair[1] : line,
                                           value: pair ? pair[2] : "")
            end
          end
        end
      end
    end
  end
end
