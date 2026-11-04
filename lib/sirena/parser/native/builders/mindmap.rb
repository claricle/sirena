# frozen_string_literal: true

require_relative "../text"
require_relative "../../builders/mindmap"

module Sirena
  module Parser
    module Native
      module Builders
        # Builds Diagram::Mindmap from the native parse tree of the
        # +mindmap+ entry. The node lines have the shape Parslet's have, so
        # the Parslet builder, which owns the hierarchy rules, reads them as
        # is.
        class Mindmap
          # @param tree [Hash, Parsanol::Slice] native parse tree
          # @return [Diagram::Mindmap]
          def apply(tree)
            nodes = tree.is_a?(Hash) ? Text.items(tree[:nodes]) : []
            result = Parser::Builders::Mindmap.new.apply(nodes: nodes)
            Parser::Mindmap.new.create_diagram(result)
          end
        end
      end
    end
  end
end
