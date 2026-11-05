# frozen_string_literal: true

require_relative "macros"

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # Splits PlantUML source into significant lines: the first diagram
        # only, comments dropped and a label that runs over several lines
        # joined into one.
        module Reader
          OPEN_QUOTE = /\A[[:alpha:]]+\s.*"[^"]*\z/
          OPEN_BRACKET = /\A[[:alpha:]]+\s+\S+\s+\[[^\]]*\z/

          module_function

          # @return [Array<Array(String, Integer)>] stripped text and its
          #   1-based line number
          def entries(source)
            lines = source.dup.force_encoding(Encoding::UTF_8).scrub.lines
            numbered = lines.each_with_index.map { |l, i| [l.strip, i + 1] }
            Macros.expand(merge(first_diagram(numbered)))
          end

          def first_diagram(numbered)
            from = numbered.index { |text, _| text.start_with?("@start") }
            body = numbered.drop(from ? from + 1 : 0)
            body.take_while { |text, _| !text.start_with?("@end") }
              .reject { |text, _| text.empty? || text.start_with?("'") }
          end

          def merge(entries)
            queue = entries.dup
            result = []
            until queue.empty?
              text, number = queue.shift
              text = "#{text}\n#{queue.shift.first}" while open?(text) &&
                  !queue.empty?
              result << [text, number]
            end
            result
          end

          def open?(text)
            text.match?(OPEN_BRACKET) ||
              (text.match?(OPEN_QUOTE) && text.count('"').odd?)
          end
        end
      end
    end
  end
end
