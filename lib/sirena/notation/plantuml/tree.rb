# frozen_string_literal: true

require_relative "tree/reader"
require_relative "tree/mindmap_layout"
require_relative "tree/wbs_layout"
require_relative "tree/renderer"

module Sirena
  module Notation
    module PlantUML
      # The PlantUML mindmap (`@startmindmap`) and work breakdown structure
      # (`@startwbs`). The front end reads either into the hierarchy graph
      # Sirena's mindmap uses; the layouts and the renderer are PlantUML's
      # own, because Mermaid's mindmap is a force layout of coloured shapes
      # and PlantUML draws a tree. Dispatched to from {PlantUML.parse}.
      module Tree
        extend self

        # kind => [IR graph id, layout]
        KINDS = {
          "mindmap" => ["mindmap", MindmapLayout],
          "wbs" => ["wbs", WbsLayout],
        }.freeze
        private_constant :KINDS

        # @param source [String] PlantUML source
        # @param kind [String] "mindmap" or "wbs"
        # @return [Notation::Parsed]
        def parse(source, kind)
          id, layout = KINDS.fetch(kind)
          Notation::Parsed.new(
            type: :mindmap, diagram: Reader.new.parse(source, id: id),
            transform: layout, renderer: Renderer
          )
        end
      end
    end
  end
end
