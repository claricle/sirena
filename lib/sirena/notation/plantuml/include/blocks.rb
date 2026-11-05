# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Include
        # Which lines of an included file a directive keeps.
        module Blocks
          START_SUB = /\A!startsub[ \t]+(?<name>\S+)\z/
          END_SUB = /\A!endsub\b/
          BLOCK_START = /\A@start\w+/
          BLOCK_END = /\A@end\w+/
          private_constant :START_SUB, :END_SUB, :BLOCK_START, :BLOCK_END

          module_function

          # @param text [String] file bytes or text
          # @return [Array<String>] its lines, UTF-8, line endings removed
          def lines_of(text)
            text.dup.force_encoding(Encoding::UTF_8).scrub.lines.map(&:chomp)
          end

          # @param kind [String] "include" or "includesub"
          # @param selector [String, nil] the part after `!`
          # @return [Array<String>]
          # @raise [Error] an `!includesub` of a name the file lacks
          def pick(kind, lines, name, selector)
            return first_block(lines) if kind == "include"

            subs = sub_blocks(lines, selector)
            return subs unless subs.empty?

            raise Error, "cannot include #{name}!#{selector}"
          end

          # @return [Array<String>] LINES without `!startsub` / `!endsub`
          def strip_subs(lines)
            lines.reject do |line|
              text = line.strip
              text.match?(START_SUB) || text.match?(END_SUB)
            end
          end

          def first_block(lines)
            from = lines.index { |line| line.strip.match?(BLOCK_START) }
            return lines unless from

            body = lines.drop(from + 1)
            stop = body.index { |line| line.strip.match?(BLOCK_END) }
            stop ? body.take(stop) : body
          end

          def sub_blocks(lines, name)
            current = nil
            lines.select do |line|
              text = line.strip
              current = START_SUB.match(text)&.[](:name) || current
              current = nil if text.match?(END_SUB)
              current == name && !text.match?(START_SUB)
            end
          end
        end
      end
    end
  end
end
