# frozen_string_literal: true

require_relative "../text"
require_relative "../../builders/block"

module Sirena
  module Parser
    module Native
      module Builders
        # Builds Diagram::Block from the native parse tree of the +block+
        # entry.
        #
        # The native tree has the shape Parslet's has -- a header node
        # followed by the statement nodes, whose position in that list names
        # anonymous blocks -- so the Parslet builder, which owns the model
        # rules, reads it as is. One thing differs: the Parslet builder
        # stringifies an arrow block's direction node, slice offset
        # included, and a native slice counts bytes where Parslet counts
        # characters.
        class Block
          # A direction that inspects as Parslet's slice does.
          class CharacterSlice
            def initialize(slice)
              @text = slice.to_s
              @offset = slice.input.byteslice(0, slice.bytepos).length
            end

            def inspect
              "#{@text.inspect}@#{@offset}"
            end
          end
          private_constant :CharacterSlice

          # @param tree [Hash] native parse tree
          # @return [Diagram::Block]
          def apply(tree)
            statements = Text.items(tree[:statements]).map { |s| fix(s) }
            Parser::Builders::Block.new
              .apply([{ header: tree[:header] }, *statements])
          end

          private

          def fix(statement)
            direction = statement[:arrow_direction]
            nested = statement[:compound_statements]
            return statement unless direction || nested

            statement.merge(fixed_direction(direction), fixed_children(nested))
          end

          def fixed_direction(direction)
            return {} unless direction

            { arrow_direction: { direction:
              CharacterSlice.new(direction[:direction]) } }
          end

          def fixed_children(nested)
            return {} unless nested

            { compound_statements: Text.items(nested).map { |s| fix(s) } }
          end
        end
      end
    end
  end
end
