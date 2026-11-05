# frozen_string_literal: true

require_relative "ebnf/reader"
require_relative "ebnf/layout"
require_relative "drawing"

module Sirena
  module Notation
    module PlantUML
      # The PlantUML EBNF diagram (`@startebnf`): each rule drawn as a
      # railroad diagram.
      module Ebnf
        extend self

        STARTER = /\A(?:\xEF\xBB\xBF)?(?:[ \t]*(?:'[^\n]*)?\r?\n)*
                   [ \t]*@startebnf(?![A-Za-z0-9_])/xn
        private_constant :STARTER

        # @return [Boolean] whether the source opens an EBNF diagram
        def ebnf?(source)
          source.b.match?(STARTER)
        end

        # @return [Notation::Parsed]
        def parse(source)
          Notation::Parsed.new(
            type: :ebnf_diagram, diagram: Reader.new.parse(source),
            transform: Layout, renderer: Drawing::Renderer
          )
        end
      end
    end
  end
end
