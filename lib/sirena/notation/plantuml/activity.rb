# frozen_string_literal: true

require_relative "style"
require_relative "activity/parser"
require_relative "activity/layout"
require_relative "activity/renderer"

module Sirena
  module Notation
    module PlantUML
      # The PlantUML activity diagram, in the new and the legacy syntax.
      # Dispatched to from {PlantUML.parse}.
      module Activity
        extend self

        # Lines only an activity diagram has. A sequence declaration or a
        # class declaration anywhere in the source wins over these.
        MARKER = /\A(?:start|stop|kill)\z|\A(?:\#\w+)?:|\A\(\*|\Aif\s*[("]|
                  \Awhile\s*\(|\Arepeat\b|\Aswitch\s*\(|\Afork\z|
                  \Apartition\s/xi
        OTHER = /\A(?:abstract[ \t]+class|class|interface|participant|actor|
                 boundary|control|entity|database|collections|queue|
                 autonumber|newpage|alt|loop|opt|par|critical|break|
                 ref)\b/xi
        private_constant :MARKER, :OTHER

        # @return [Boolean] whether the source reads as an activity diagram
        def activity?(source)
          lines = source.dup.force_encoding(Encoding::UTF_8).scrub.lines
          lines = lines.map(&:strip)
          lines.none? { |line| OTHER.match?(line) } &&
            lines.any? { |line| MARKER.match?(line) }
        end

        # @return [Notation::Parsed]
        def parse(source)
          sheet = Style::Reader.read(source)
          diagram = Parser.new.parse(source)
          diagram.style = sheet
          Notation::Parsed.new(
            type: :activity_diagram,
            diagram: diagram,
            transform: Layout,
            renderer: Style::Bound.wrap(Renderer, sheet),
          )
        end
      end
    end
  end
end
