# frozen_string_literal: true

require_relative "sequence/layout"
require_relative "sequence/parser"
require_relative "sequence/renderer"

module Sirena
  module Notation
    module PlantUML
      # The PlantUML sequence diagram, as far as participants and plain
      # messages. Dispatched to from {PlantUML.parse}.
      module Sequence
        extend self

        # Declarations and arrows that only sequence diagrams use. A class
        # declaration wins: a class body may mention these words.
        MARKER = /\A(?:participant|actor|boundary|control|entity|database|
                  collections|queue|activate|deactivate|autonumber|newpage|
                  alt|loop|opt|par|critical|break|ref)\b
                  |\A==|\A(?:"[^"]*"|\w+)[ \t]*(?:->|<<?-(?!-))/xi
        CLASS = /\A(?:abstract[ \t]+class|class|interface)[ \t]/i
        private_constant :MARKER, :CLASS

        # @return [Boolean] whether the source reads as a sequence diagram
        def sequence?(source)
          lines = source.dup.force_encoding(Encoding::UTF_8).scrub.lines
          lines = lines.map(&:strip)
          lines.none? { |line| CLASS.match?(line) } &&
            lines.any? { |line| MARKER.match?(line) }
        end

        # @return [Notation::Parsed]
        def parse(source)
          Notation::Parsed.new(
            type: :sequence_diagram,
            diagram: Parser.new.parse(source),
            transform: Layout,
            renderer: Renderer,
          )
        end
      end
    end
  end
end
