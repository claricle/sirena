# frozen_string_literal: true

require_relative "../../diagram/error"

module Sirena
  module Parser
    module Builders
      # Transform for converting Parslet parse tree to Error diagram model.
      #
      # Converts the parse tree output from Grammars::Error into a
      # fully-formed Diagram::Error object.
      class Error
        # Transform parse tree into Error diagram.
        #
        # @param tree [Array, Hash] Parslet parse tree
        # @return [Diagram::Error] the error diagram model
        def apply(tree)
          diagram = Diagram::Error.new

          [tree].flatten(1).each do |item|
            process_message(diagram, item) if item.key?(:message)
          end

          diagram
        end

        private

        def process_message(diagram, item)
          message = item[:message]
          return unless message

          # Extract message text
          message_text = extract_text(message)
          diagram.message = message_text unless message_text.empty?
        end

        def extract_text(value)
          case value
          when Hash
            value.values.first.to_s
          when String
            value
          else
            value.to_s
          end.strip
        end
      end
    end
  end
end
