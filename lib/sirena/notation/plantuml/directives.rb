# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # Lines that restyle or steer a diagram without adding to its model:
      # which layout engine PlantUML uses, what it hides, its skin
      # parameters, its layout direction. The parser records them in the
      # Diagram's `directives`; nothing in this notation applies them yet.
      module Directives
        extend self

        TARGET = '(?:[A-Za-z_][A-Za-z0-9_]*[ \t]+|<<[^<>\s]+>>[ \t]+)'
        PATTERNS = [
          /\A!pragma[ \t]+(?:layout[ \t]+(?:smetana|dot)|
            svginteractive[ \t]+(?:true|false))\z/ix,
          /\A(?:hide|show)[ \t]+(?:empty[ \t]+)?#{TARGET}?
            (?:members|attributes|methods|fields|circle|stereotype)\z/ix,
          /\Askinparam[ \t]+[A-Za-z0-9_.]+(?:<<[^<>\s]+>>)?[ \t]+
            [^{}\s][^{}]*\z/ix,
          /\A(?:left to right|top to bottom) direction\z/i,
        ].freeze
        private_constant :TARGET, :PATTERNS

        # @param text [String] one stripped source line
        def match?(text)
          PATTERNS.any? { |pattern| pattern.match?(text) }
        end
      end
    end
  end
end
