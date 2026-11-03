# frozen_string_literal: true

require_relative "../text"
require_relative "../../builders/sequence"

module Sirena
  module Parser
    module Native
      module Builders
        # Builds Diagram::Sequence from the native parse tree of the
        # +sequence+ entry. Its statements have the shape Parslet's do,
        # except that a list of one comes back as the bare statement, so
        # the lists are rebuilt as arrays before the Parslet builder,
        # which owns the participant, message and frame rules, reads them.
        class Sequence
          LISTS = %i[
            box_statements loop_statements alt_statements opt_statements
            rect_statements par_statements critical_statements
            break_statements else_blocks and_blocks option_blocks
            else_statements and_statements option_statements
          ].freeze
          private_constant :LISTS

          # @param tree [Hash, Parsanol::Slice] native parse tree
          # @return [Diagram::Sequence]
          def apply(tree)
            statements = tree.is_a?(Hash) ? tree[:statements] : nil
            Parser::Builders::Sequence.new.apply(
              [{ header: "sequenceDiagram" }] + plain_list(statements),
            )
          end

          private

          def plain_list(value)
            Text.items(value).map { |statement| plain(statement) }
          end

          def plain(statement)
            statement.to_h do |key, value|
              [key, LISTS.include?(key) ? plain_list(value) : value]
            end
          end
        end
      end
    end
  end
end
