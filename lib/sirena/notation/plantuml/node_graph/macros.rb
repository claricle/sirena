# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # `!define NAME body`: PlantUML's object-like macro. The definition
        # is dropped and each later whole-word `NAME` becomes `body`.
        # A macro with parameters is left alone, so the parser still names
        # it as a preprocessor line.
        module Macros
          DEFINE = /\A!define\s+(?<name>\w+)(?:\s+(?<body>.*))?\z/

          module_function

          # @param entries [Array<Array(String, Integer)>] text and line number
          # @return [Array<Array(String, Integer)>] the entries with every
          #   plain definition expanded
          def expand(entries)
            table = {}
            entries.filter_map do |text, number|
              if (match = text.match(DEFINE))
                table[match[:name]] = substitute(match[:body].to_s, table)
                next
              end
              [substitute(text, table), number]
            end
          end

          def substitute(text, table)
            table.reduce(text) do |line, (name, body)|
              line.gsub(/(?<!\w)#{Regexp.escape(name)}(?!\w)/) { body }
            end
          end
        end
      end
    end
  end
end
