# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # Splits explicit message lines and wraps each to `Maxmessagesize`.
        # Words fill a line until the next one would pass the limit; a word
        # wider than the limit keeps a line.
        class MessageWrap
          # @param limit [Numeric, nil] widest line, in pixels; nil never wraps
          # @param measure [#call] text width in pixels
          def initialize(limit, measure)
            @limit = limit
            @measure = measure
          end

          # @return [Array<String>] the lines of `label`
          def lines(label)
            explicit_lines(label).flat_map { |line| wrapped_line(line) }
          end

          # @return [Float] the width of the widest line of `label`
          def width(label)
            lines(label).map { |line| @measure.call(line) }.max.to_f
          end

          private

          def explicit_lines(label)
            decoded = decode_line_breaks(label)
            decoded = decode_quote_escapes(decoded) if doubled_quotes?(label)
            if !decoded.include?("\n") && doubled_quotes?(decoded)
              decoded = decoded[2...-2].strip
            end
            decoded.empty? ? [""] : decoded.split(/\r\n|\r|\n/, -1)
          end

          def decode_line_breaks(label)
            label.gsub(/(\\+)n/) do
              slashes = Regexp.last_match(1).size
              ("\\" * (slashes / 2)) + (slashes.odd? ? "\n" : "n")
            end
          end

          def decode_quote_escapes(label)
            label.gsub(/\\+(?![\\n])/) do |slashes|
              "\\" * ((slashes.size + 1) / 2)
            end
          end

          def doubled_quotes?(label)
            label.start_with?('""') && label.end_with?('""')
          end

          def wrapped_line(line)
            return [line] unless @limit

            words = line.split(/[ \t]+/)
            return [""] if words.empty?

            words.each_with_object([]) { |word, lines| add(lines, word) }
          end

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
