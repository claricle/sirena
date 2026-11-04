# frozen_string_literal: true

require_relative "../declined"
require_relative "../text"
require_relative "../../builders/state_diagram"

module Sirena
  module Parser
    module Native
      module Builders
        # Builds Diagram::StateDiagram from the native parse tree of the
        # +state_diagram+ entry. The native grammar captures under the
        # names of the Parslet grammar, so the Parslet builder, which owns
        # the model rules, reads the tree as is; only list shapes and the
        # nesting depth are looked at first.
        class StateDiagram
          # The Parslet grammar gives out on deeply nested composites and
          # reports an error. A deeper tree is left to it so the answer
          # stays that error.
          MAX_NESTING = 64

          # @param tree [Hash, Array] native parse tree
          # @return [Diagram::StateDiagram]
          # @raise [Declined] for a tree nested deeper than MAX_NESTING
          def apply(tree)
            items = Text.items(tree)
            raise Declined if too_deep?(items, 0)

            Parser::Builders::StateDiagram.new.apply(items.map { |i| lists(i) })
          end

          private

          def too_deep?(statements, depth)
            statements.any? do |stmt|
              inner = depth + 1
              next false unless stmt.key?(:composite)

              inner > MAX_NESTING ||
                too_deep?(Text.items(stmt[:composite]), inner)
            end
          end

          def nested?(composite)
            composite.is_a?(Hash) || composite.is_a?(Array)
          end

          # A single-element repeat is a Hash here, an Array in Parslet.
          def lists(item)
            item = item.merge(chain: Text.items(item[:chain])) if
              item.key?(:chain)
            return item unless nested?(item[:composite])

            statements = Text.items(item[:composite])
            item.merge(composite: statements.map { |s| lists(s) })
          end
        end
      end
    end
  end
end
