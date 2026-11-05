# frozen_string_literal: true

require_relative "network/reader"
require_relative "network/layout"
require_relative "drawing"

module Sirena
  module Notation
    module PlantUML
      # The PlantUML network diagram (`nwdiag`): networks as horizontal bars
      # with the nodes that belong to them hanging below. PlantUML wants
      # `@startnwdiag`; the same block inside `@startuml` is read too.
      module Network
        extend self

        OPENER = /^[ \t]*nwdiag[ \t]*\{/
        STARTER = /\A(?:\xEF\xBB\xBF)?(?:[ \t]*(?:'[^\n]*)?\r?\n)*
                   [ \t]*@startnwdiag/xn
        private_constant :OPENER, :STARTER

        # @return [Boolean] whether the source holds an `nwdiag` block
        def network?(source)
          source.b.match?(STARTER) ||
            source.dup.force_encoding(Encoding::UTF_8).scrub.match?(OPENER)
        end

        # @return [Notation::Parsed]
        def parse(source)
          Notation::Parsed.new(
            type: :network_diagram, diagram: Reader.new.parse(source),
            transform: Layout, renderer: Drawing::Renderer
          )
        end
      end
    end
  end
end
