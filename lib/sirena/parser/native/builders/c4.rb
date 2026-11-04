# frozen_string_literal: true

require_relative "../../builders/c4"

module Sirena
  module Parser
    module Native
      module Builders
        # Builds Diagram::C4 from the native parse tree of the +c4+ entry,
        # which has the shape Parslet's tree has.
        class C4 < Parser::Builders::C4
        end
      end
    end
  end
end
