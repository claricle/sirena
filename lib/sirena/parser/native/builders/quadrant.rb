# frozen_string_literal: true

require_relative "../text"
require_relative "../../builders/quadrant"

module Sirena
  module Parser
    module Native
      module Builders
        # Builds Diagram::Quadrant from the native tree of the +quadrant+
        # entry. Its statements carry the keys the Ruby builder reads, so
        # the two paths share that builder and the classDef check.
        class Quadrant
          # @param tree [Hash] native parse tree
          # @return [Diagram::Quadrant]
          # @raise [Parser::ParseError] for an unsupported classDef style
          def apply(tree)
            items = [tree.except(:statements)]
            items.concat(Text.items(tree[:statements]))
            Parser::Quadrant.new.validate_class_styles(items)
            Parser::Builders::Quadrant.new.apply(items)
          end
        end
      end
    end
  end
end
