# frozen_string_literal: true

require_relative "gantt/reader"
require_relative "gantt/layout"
require_relative "gantt/renderer"
require_relative "../mermaid/ir_adapters/gantt"

module Sirena
  module Notation
    module PlantUML
      # The PlantUML gantt chart (`@startgantt`). The front end reads the
      # source into the Gantt model Sirena already schedules and maps it
      # through the same IR adapter; the layout and renderer are PlantUML's
      # own, because PlantUML counts days from the first and draws a table
      # beside the grid where Mermaid draws a dated axis. Dispatched to from
      # {PlantUML.parse}.
      module Gantt
        extend self

        # @param source [String] PlantUML source
        # @return [Notation::Parsed]
        def parse(source)
          model, dated = Reader.new.parse(source)
          model.axis_format = dated ? "dated" : "days"
          Notation::Parsed.new(
            type: :gantt,
            diagram: Sirena::Notation::Mermaid::IRAdapters::Gantt.call(model),
            transform: Layout, renderer: Renderer
          )
        end
      end
    end
  end
end
