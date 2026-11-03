# frozen_string_literal: true

require_relative "../text"
require_relative "../declined"
require_relative "../../builders/timeline"

module Sirena
  module Parser
    module Native
      module Builders
        # Builds Diagram::Timeline from the native tree of the +timeline+
        # entry. The statements are the items the Ruby builder reads, so
        # the two paths share its logic.
        class Timeline < Parser::Builders::Timeline
          ACCESSIBILITY_KEYS = %i[acc_title acc_descr].freeze
          private_constant :ACCESSIBILITY_KEYS

          # @param tree [Hash] native parse tree
          # @return [Diagram::Timeline]
          # @raise [Declined] for an empty accessibility text
          def apply(tree)
            items = [tree.except(:statements)]
            items.concat(Text.items(tree[:statements]))
            decline_empty_text(items)
            super(items)
          end

          private

          # Parslet leaves "[]" for an empty text; the Ruby path owns that.
          def decline_empty_text(items)
            return unless items.any? { |item| empty_text?(item) }

            raise Declined
          end

          def empty_text?(item)
            ACCESSIBILITY_KEYS.any? do |key|
              item.key?(key) && Text.empty?(item[key])
            end
          end
        end
      end
    end
  end
end
