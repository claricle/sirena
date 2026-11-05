# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Ebnf
        # What a rule's right-hand side is made of.
        Literal = Struct.new(:text, keyword_init: true)
        Reference = Struct.new(:name, keyword_init: true)
        Special = Struct.new(:text, keyword_init: true)
        Sequence = Struct.new(:items, keyword_init: true)
        Choice = Struct.new(:branches, keyword_init: true)
        Optional = Struct.new(:item, keyword_init: true)
        # `{ x }` is a Repetition with `least` 0 and `{ x }-` one with 1.
        Repetition = Struct.new(:item, :least, keyword_init: true)

        # One `name = expression ;`.
        Rule = Struct.new(:name, :expression, keyword_init: true)
      end
    end
  end
end
