# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # The text PlantUML draws for a class named in quotes. The part after
      # the last dot is the class; the parts before it are its namespaces.
      #
      # `\n`, `\r` and `\l` end a line, `\t` is a gap and `\\` is one
      # backslash. Any other backslash stays as written. `\uXXXX` is also
      # read by PlantUML and is not read here, so {escapes?} lets a caller
      # refuse it.
      module ClassName
        extend self

        LINE_BREAKS = %w[n r l].freeze
        GAP = "\u00A0" * 4
        EMPTY_LINE = "\u00A0"
        private_constant :LINE_BREAKS, :GAP, :EMPTY_LINE

        # @return [Boolean] true when `name` holds a `\u` escape
        def escapes?(name)
          name.include?("\\u")
        end

        # @return [Array<String>] the namespaces, outermost first
        def namespaces(name)
          name.split(".", -1)[0...-1]
        end

        # @return [Array<String>] the drawn lines of the class itself; a
        #   blank line is a non-breaking space so it keeps its height
        def lines(name)
          text = name.split(".", -1).last.gsub(/\\(.)/m) { unescape($1) }
          text.split("\n", -1).map do |line|
            line.strip.then { |kept| kept.empty? ? EMPTY_LINE : kept }
          end
        end

        private

        def unescape(char)
          return "\n" if LINE_BREAKS.include?(char)
          return GAP if char == "t"

          char == "\\" ? "\\" : "\\#{char}"
        end
      end
    end
  end
end
