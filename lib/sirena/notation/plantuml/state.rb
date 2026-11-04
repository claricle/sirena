# frozen_string_literal: true

require_relative "../../parser/state_diagram"
require_relative "../../layout/state_diagram"
require_relative "../../renderer/state_diagram"
require_relative "../mermaid/ir_adapters/state_diagram"
require_relative "state/reader"

module Sirena
  module Notation
    module PlantUML
      # The PlantUML state diagram. The front end reads PlantUML's source into
      # the state model Sirena already lays out and draws, so the picture is
      # the one a Mermaid state diagram gets. Dispatched to from
      # {PlantUML.parse}.
      module State
        extend self

        # Lines only a state diagram has: a `state` declaration or a
        # transition from or to the initial/final marker.
        MARKER = /\A(?:state\s+(?!.*(?:-+>|<-+))\S|
                   \[\*\][ \t]*-+(?:[a-z]+-+)?>|<-+[ \t]*\[\*\]|
                   \S+[ \t]+-+(?:[a-z]+-+)?>[ \t]*\[\*\])/xi
        # Lines another family owns; a source with one is never claimed.
        OTHER = /\A(?:class|abstract|interface|enum|participant|actor|
                 usecase|component|start|partition|fork)\b/xi
        private_constant :MARKER, :OTHER

        # @return [Boolean] whether the source reads as a state diagram
        def state?(source)
          lines = Reader.lines_of(source).map(&:first)
          lines.none? { |line| OTHER.match?(line) } &&
            lines.any? { |line| MARKER.match?(line) }
        end

        # @return [Notation::Parsed]
        def parse(source)
          model = Reader.new.parse(source)
          Notation::Parsed.new(
            type: :state_diagram,
            diagram: Sirena::Notation::Mermaid::IRAdapters::StateDiagram.call(model),
            transform: Sirena::Layout::StateDiagram,
            renderer: Sirena::Renderer::StateDiagram,
          )
        end
      end
    end
  end
end
