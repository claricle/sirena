# frozen_string_literal: true

require_relative "common"

module Sirena
  module Parser
    module Grammars
      # Parslet grammar for error diagrams.
      #
      # Mermaid only detects a source that is exactly "error" (any case
      # in its detector, trimmed); "Error Diagrams" is no diagram there.
      #
      # @example Simple error diagram
      #   error
      class Error < Common
        root(:diagram)

        # Main diagram structure
        rule(:diagram) do
          ws? >>
            header >>
            ws?
        end

        # Header: error or Error, alone
        rule(:header) do
          (str("Error") | str("error")).as(:header) >> ws?
        end
      end
    end
  end
end
