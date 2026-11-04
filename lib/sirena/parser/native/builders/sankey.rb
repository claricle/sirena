# frozen_string_literal: true

require_relative "../../builders/sankey"

module Sirena
  module Parser
    module Native
      module Builders
        # Builds Diagram::Sankey from the native tree of the +sankey+ entry.
        #
        # The entry's tree ({header:, statements: [...]}) has the shape the
        # Ruby builder already reads, so the two paths share one builder.
        class Sankey < Parser::Builders::Sankey
        end
      end
    end
  end
end
