# frozen_string_literal: true

require_relative 'common'

module Sirena
  module Parser
    module Grammars
      # Parslet grammar for error diagrams.
      #
      # Handles simple error diagram syntax with optional error message.
      #
      # @example Simple error diagram
      #   error
      #
      # @example Error diagram with message
      #   Error Diagrams
      class Error < Common
        root(:diagram)

        # Main diagram structure
        rule(:diagram) do
          ws? >>
            header >>
            ws?
        end

        # Header: error [message text] or Error [message text]
        rule(:header) do
          (str('Error') | str('error')).as(:header) >>
            (space.repeat(1) >> message_text).maybe.as(:message) >>
            ws?
        end

        rule(:message_text) do
          (line_end.absent? >> any).repeat(1)
        end
      end
    end
  end
end