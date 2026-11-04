# frozen_string_literal: true

require_relative "../text"
require_relative "../../builders/er_diagram"

module Sirena
  module Parser
    module Native
      module Builders
        # Builds Diagram::ErDiagram from the native parse tree of the
        # +er_diagram+ entry. The statement nodes have the shape Parslet's
        # have, so the Parslet builder, which owns the model rules, reads
        # them once an empty note (an Array in the native tree, a Slice in
        # Parslet's) is spelled as the empty string.
        class ErDiagram
          # @param tree [Hash] native parse tree
          # @return [Diagram::ErDiagram]
          def apply(tree)
            statements = Text.items(tree[:statements]).map do |statement|
              normalize(statement)
            end
            Parser::Builders::ErDiagram.new.apply(statements)
          end

          private

          def normalize(statement)
            return statement unless statement.key?(:attributes)

            statement.merge(
              attributes: Text.items(statement[:attributes]).map do |attr|
                normalize_attribute(attr)
              end,
            )
          end

          def normalize_attribute(attribute)
            note = attribute[:note]
            return attribute unless note.is_a?(Hash)

            attribute.merge(note: { string: Text.of(note[:string]) })
          end
        end
      end
    end
  end
end
