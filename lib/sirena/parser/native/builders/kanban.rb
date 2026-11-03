# frozen_string_literal: true

require_relative "../text"
require_relative "../../builders/kanban"

module Sirena
  module Parser
    module Native
      module Builders
        # Builds Diagram::Kanban from the native parse tree of the +kanban+
        # entry. The lines have the shape Parslet's have, so the Parslet
        # builder, which owns the board rules, reads them as is. A capture
        # that matched no characters is an Array in the native tree where
        # Parslet holds an empty slice, so those are read as text first.
        class Kanban
          # @param tree [Hash, Parsanol::Slice] native parse tree
          # @return [Diagram::Kanban]
          def apply(tree)
            lines = tree.is_a?(Hash) ? Text.items(tree[:lines]) : []
            result = Parser::Builders::Kanban.new
              .apply(lines: lines.map { |line| plain(line) })
            Parser::Kanban.new.create_diagram(result)
          end

          private

          def plain(line)
            line = line.merge(indent: Text.of(line[:indent])) if line[:indent]
            return line unless line[:metadata]

            line.merge(metadata: { body: Text.of(line[:metadata][:body]) })
          end
        end
      end
    end
  end
end
