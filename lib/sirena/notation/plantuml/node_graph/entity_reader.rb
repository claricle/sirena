# frozen_string_literal: true

require_relative "crows_foot"
require_relative "references"

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # What the node parser needs for entity diagrams: the
        # `entity Name { fields }` block and the cardinality links between
        # entities.
        module EntityReader
          Field = Struct.new(:text, :key)

          ENTITY = /\Aentity\s+(?<rest>.+?)(?:\s*(?<open>\{))?\z/im
          DIVIDER = /\A([-=._])\1(?:.*\1\1)?\z/

          private

          def take_entity(text)
            return unless (match = text.match(ENTITY))

            node = declare(:entity, match[:rest])
            node.sections = match[:open] ? read_sections : []
            node
          end

          def take_er_edge(text)
            return unless (match = text.match(References::ER_EDGE))

            add_edge(match, Link.new(match[:line]))
            @graph.edges.last.ends = CrowsFoot.parse(match[:l], match[:r])
          end

          # Reads field lines up to the closing brace into sections that a
          # divider line (`--`, `==`, `..`, `__`) separates.
          def read_sections
            sections = [[]]
            block_lines.each do |line|
              next sections << [] if line.match?(DIVIDER)

              sections.last << field(line)
            end
            sections.reject(&:empty?)
          end

          def block_lines
            from = @index
            @index += 1 until @index >= @entries.size ||
                @entries[@index].first == "}"
            @index += 1
            @entries[from...(@index - 1)].map(&:first)
          end

          def field(line)
            key = line.start_with?("*")
            text = line.delete_prefix("*").strip
            Field.new(text.gsub(/<<\s*(.*?)\s*>>/, "«\\1»"), key)
          end
        end
      end
    end
  end
end
