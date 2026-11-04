# frozen_string_literal: true

require_relative "node_graph/parser"
require_relative "node_graph/layout"
require_relative "node_graph/renderer"

module Sirena
  module Notation
    module PlantUML
      # The node-and-link model use case and component diagrams share: a
      # parser, a ranked layout and a renderer. {Usecase} and {Component}
      # decide which source they claim.
      module NodeGraph
        # Lines another family owns; a source with one is never claimed.
        FOREIGN = /\A(?:participant|class|abstract|enum|boundary|control|
                   entity|collections|queue|autonumber|newpage|alt|loop|opt|
                   par|critical|break|ref|fork|partition|
                   repeat|while|switch|if)\b|;\z|\A\(\*|\Astate\b|
                   \A(?:start|stop)\z/xi

        module_function

        # @return [Array<String>] the stripped lines of the first diagram
        def lines_of(source)
          Reader.entries(source).map(&:first)
        end

        # @return [Notation::Parsed]
        def parsed(source, type:, direction:, default_kind:)
          graph = Parser.new(direction: direction, default_kind: default_kind)
            .parse(source)
          Notation::Parsed.new(type: type, diagram: graph, transform: Layout,
                               renderer: Renderer)
        end
      end
    end
  end
end
