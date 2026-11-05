# frozen_string_literal: true

require_relative "../plantuml_data/boxes/graph_layout"
require_relative "../plantuml_data/boxes/renderer"
require_relative "objects/reader"

module Sirena
  module Notation
    module PlantUML
      # The PlantUML object diagram: `object`, `map` and `json` elements and
      # the relations between them, drawn as boxes. Dispatched to from
      # {PlantUML.parse}.
      module Objects
        extend self

        # An element only an object diagram has; the families tried before
        # this one have already refused the source.
        ELEMENT = /\A(?:object[ \t]+["A-Za-z_]|
                   map[ \t]+(?:"[^"]+"[ \t]+as[ \t]+\w+|\w[\w.]*)[ \t]*\{)/x
        private_constant :ELEMENT

        # @return [Boolean] whether the source reads as an object diagram
        def objects?(source)
          Reader.lines_of(source).any? { |line, _| ELEMENT.match?(line) }
        end

        # @return [Notation::Parsed]
        def parse(source)
          Notation::Parsed.new(
            type: :object_diagram,
            diagram: Reader.new.parse(source),
            transform: PlantUMLData::Boxes::GraphLayout,
            renderer: PlantUMLData::Boxes::Renderer,
          )
        end
      end
    end
  end
end
