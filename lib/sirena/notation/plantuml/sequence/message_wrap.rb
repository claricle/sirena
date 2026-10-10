# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # Breaks a message label into the lines PlantUML draws when
        # `Maxmessagesize` is set: words fill a line until the next one would
        # pass the limit, and a word wider than the limit keeps a line.
        class MessageWrap
          # @param limit [Numeric, nil] widest line, in pixels; nil never wraps
          # @param measure [#call] text width in pixels
          def initialize(limit, measure)
            @limit = limit
            @measure = measure
          end

          # @return [Array<String>] the lines of `label`
          def lines(label)
            return [label] unless @limit

            label.split(/[ \t]+/).each_with_object([]) do |word, lines|
              add(lines, word)
            end
          end

          # @return [Float] the width of the widest line of `label`
          def width(label)
            lines(label).map { |line| @measure.call(line) }.max.to_f
          end

          private

          def add(lines, word)
            joined = "#{lines.last} #{word}"
            if lines.empty? || @measure.call(joined) > @limit
              lines << word
            else
              lines[-1] = joined
            end
          end
        end
      end
    end
  end
end
