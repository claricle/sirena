# frozen_string_literal: true

require_relative "../../../diagram/info"

module Sirena
  module Parser
    module Native
      module Builders
        # Builds Diagram::Info from the native parse tree of the +info+ entry.
        class Info
          # @param tree [Hash, Parsanol::Slice] native parse tree
          # @return [Diagram::Info]
          def apply(tree)
            Diagram::Info.new.tap do |diagram|
              diagram.show_info = true if show_info?(tree)
            end
          end

          private

          def show_info?(tree)
            return false unless tree.is_a?(Hash)

            tree.key?(:show_info) || tree.key?(:body)
          end
        end
      end
    end
  end
end
