# frozen_string_literal: true

require_relative '../../diagram/error'

module Sirena
  module Parser
    module Transforms
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

          # Process tree structure
          if tree.is_a?(Array)
            tree.each do |item|
              next unless item.is_a?(Hash)

              process_message(diagram, item) if item.key?(:message)
            end
          elsif tree.is_a?(Hash)
            process_message(diagram, tree) if tree.key?(:message)
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