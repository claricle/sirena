# frozen_string_literal: true

require_relative "legacy_parser"
require_relative "new_parser"
require_relative "../unsupported_construct_error"

module Sirena
  module Notation
    module PlantUML
      module Activity
        # Reads PlantUML activity source into a {Diagram}, in whichever of
        # the two syntaxes it is written.
        class Parser
          # @param source [String]
          # @return [Diagram]
          # @raise [UnsupportedConstructError]
          def parse(source)
            entries = Parser.entries(source)
            if Parser.legacy?(entries.map(&:first))
              LegacyParser.new.parse(entries)
            else
              NewParser.new.parse(entries)
            end
          end

          # @return [Array<Array(String, Integer)>] each significant line,
          #   stripped, with its 1-based number
          def self.entries(source)
            lines = source.dup.force_encoding(Encoding::UTF_8).scrub.lines
            lines.each_with_index.filter_map do |line, index|
              text = line.strip
              next if text.empty? || text.start_with?("'", "@start", "@end")

              refuse_style(text, index + 1)
              [text, index + 1]
            end
          end

          # @return [Boolean] whether any line is legacy-only syntax
          def self.legacy?(lines)
            lines.any? do |line|
              line.include?("(*") || line.match?(/\Aif\s+"/i)
            end
          end

          def self.refuse_style(text, number)
            return unless text.match?(/\A<style>/i)

            raise UnsupportedConstructError.new(construct: "style block",
                                                line: number, text: text)
          end
          private_class_method :refuse_style
        end
      end
    end
  end
end
