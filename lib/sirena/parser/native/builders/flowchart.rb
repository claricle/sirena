# frozen_string_literal: true

require_relative "../declined"
require_relative "../../builders/flowchart"

module Sirena
  module Parser
    module Native
      module Builders
        # Builds Diagram::Flowchart from the native parse tree of the
        # +flowchart+ entry. The native grammar captures under the names
        # of the Parslet grammar, so the Parslet builder, which owns the
        # model rules, reads the tree as is; only list shapes and the
        # nesting depth are looked at first.
        class Flowchart
          # The Parslet grammar gives out under 190 nested boxes and
          # reports a diagram that nests too deeply. A deeper tree is
          # left to it so the answer stays that error.
          MAX_NESTING = 64

          # @param tree [Hash, Array] native parse tree
          # @return [Diagram::Flowchart]
          # @raise [Declined] for a tree nested deeper than MAX_NESTING
          def apply(tree)
            items = [tree].flatten(1)
            raise Declined if too_deep?(items, 0)

            Parser::Builders::Flowchart.new.apply(items.map { |i| lists(i) })
          end

          private

          def too_deep?(statements, depth)
            statements.any? do |stmt|
              next false unless stmt.is_a?(Hash) && stmt[:subgraph_keyword]

              inner = depth + 1
              inner > MAX_NESTING ||
                too_deep?([stmt[:subgraph_statements]].flatten(1), inner)
            end
          end

          # A single-element repeat is a Hash here, an Array in Parslet.
          def lists(item)
            return item unless item.is_a?(Hash)

            item = item.merge(group: [item[:group]].flatten(1)) if
              item.key?(:group)
            return item unless item[:subgraph_statements]

            statements = [item[:subgraph_statements]].flatten(1)
            item.merge(subgraph_statements: statements.map { |s| lists(s) })
          end
        end
      end
    end
  end
end
