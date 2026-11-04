# frozen_string_literal: true

require_relative "../text"
require_relative "../../../error/parse_error"
require_relative "../../../diagram/packet"

module Sirena
  module Parser
    module Native
      module Builders
        # Builds Diagram::Packet from the native tree of the +packet+ entry.
        class Packet
          # @param tree [Hash, Parsanol::Slice] native parse tree
          # @return [Diagram::Packet]
          # @raise [Parser::ParseError] for a reversed or gapped bit range
          def apply(tree)
            diagram = Diagram::Packet.new
            @next_bit = 0
            statements(tree).each { |item| apply_item(diagram, item) }
            diagram
          end

          private

          def statements(tree)
            return [] unless tree.is_a?(Hash)

            Text.items(tree[:statements])
          end

          def apply_item(diagram, item)
            return diagram.title = item[:title].to_s if item.key?(:title)

            diagram.add_field(field(item))
          end

          def field(item)
            first = item[:bit_start].to_s.to_i
            last = item.key?(:bit_end) ? item[:bit_end].to_s.to_i : first
            check_range(first, last)
            @next_bit = last + 1
            Diagram::PacketField.new(first, last, label(item[:label]))
          end

          def check_range(first, last)
            if last < first
              raise Parser::ParseError,
                    "Packet field end must be greater than or equal to start."
            end
            return if first == @next_bit

            raise Parser::ParseError,
                  "Packet fields must start from #{@next_bit}."
          end

          def label(capture)
            Text.of(capture).gsub(/\\(.)/m, '\\1')
          end
        end
      end
    end
  end
end
