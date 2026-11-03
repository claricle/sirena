# frozen_string_literal: true

require_relative "../text"
require_relative "../../builders/requirement"

module Sirena
  module Parser
    module Native
      module Builders
        # Builds Diagram::Requirement from the native parse tree of the
        # +requirement+ entry. The statement nodes have the shape Parslet's
        # have, so the Parslet builder, which owns the model rules, reads
        # them as is.
        class Requirement
          # @param tree [Hash] native parse tree
          # @return [Diagram::Requirement]
          def apply(tree)
            Parser::Builders::Requirement.new
              .apply(Text.items(tree[:statements]))
          end
        end
      end
    end
  end
end
