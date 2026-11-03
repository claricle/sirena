# frozen_string_literal: true

require_relative "../text"
require_relative "../declined"
require_relative "../../../error/parse_error"
require_relative "../../../diagram/pie"

module Sirena
  module Parser
    module Native
      module Builders
        # Builds Diagram::Pie from the native parse tree of the +pie+ entry.
        class Pie
          # @param tree [Hash, Array, Parsanol::Slice] native parse tree
          # @return [Diagram::Pie]
          # @raise [Declined] for an empty title or accessibility text
          # @raise [Parser::ParseError] for a negative slice value
          def apply(tree)
            Diagram::Pie.new.tap do |diagram|
              Text.items(tree).each { |item| apply_item(diagram, item) }
            end
          end

          private

          def apply_item(diagram, item)
            diagram.show_data = true if item.key?(:show_data)
            diagram.title = title_text(item[:title]) if item.key?(:title)
            apply_statement(diagram, item)
          end

          def apply_statement(diagram, item)
            return add_slice(diagram, item[:entry]) if item.key?(:entry)

            apply_text(diagram, item)
          end

          TEXT_ATTRIBUTES = {
            acc_title: :acc_title=,
            acc_descr: :acc_description=,
            standalone_title: :title=,
          }.freeze
          private_constant :TEXT_ATTRIBUTES

          def apply_text(diagram, item)
            key = TEXT_ATTRIBUTES.keys.find { |name| item.key?(name) }
            return unless key

            diagram.public_send(TEXT_ATTRIBUTES[key],
                                accessibility_text(item[key]))
          end

          def title_text(node)
            accessibility_text(node)
          end

          # Parslet leaves "[]" for an empty text; the Ruby path owns that.
          def accessibility_text(node)
            raise Declined if Text.empty?(node[:text])

            Text.of(node[:text]).strip
          end

          def add_slice(diagram, entry)
            slice = Diagram::PieSlice.new
            slice.label = Text.of(entry[:label][:string]).strip
            slice.value = slice_value(entry[:value])
            diagram.slices << slice
          end

          def slice_value(raw)
            value = raw.to_s.to_f
            return value unless value.negative?

            raise Parser::ParseError,
                  "Negative values are not allowed in pie charts."
          end
        end
      end
    end
  end
end
