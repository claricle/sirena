# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # The lines of a PlantUML source's first diagram, for the families
      # that read line by line.
      module SourceLines
        module_function

        # @param source [String] PlantUML source, valid UTF-8 or not
        # @return [Array<Array(String, Integer)>] each line stripped, with
        #   its 1-based number; blank and `'` comment lines dropped
        def of(source)
          text = source.dup.force_encoding(Encoding::UTF_8).scrub
          inside(numbered(text)).reject do |line, _|
            line.empty? || line.start_with?("'")
          end
        end

        def numbered(text)
          text.lines.map.with_index { |line, index| [line.strip, index + 1] }
        end

        def inside(lines)
          opened = lines.drop_while { |line, _| !line.start_with?("@start") }
          opened.drop(1).take_while { |line, _| !line.start_with?("@end") }
        end
        private_class_method :numbered, :inside
      end
    end
  end
end
