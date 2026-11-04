# frozen_string_literal: true

require_relative "../text"
require_relative "../../builders/treemap"

module Sirena
  module Parser
    module Native
      module Builders
        # Builds Diagram::Treemap from the native tree of the +treemap+
        # entry: native statements become the intermediate statement list
        # the Ruby builder turns into the node hierarchy.
        class Treemap
          # @param tree [Hash] native parse tree
          # @return [Diagram::Treemap]
          def apply(tree)
            statements = Text.items(tree[:statements]).filter_map do |item|
              statement(item)
            end
            Parser::Builders::Treemap.new.build_diagram(statements:)
          end

          private

          def statement(item)
            return title(item) if item.key?(:title)
            return class_def(item[:class_def]) if item.key?(:class_def)
            return node(item[:node]) if item.key?(:node)

            nil
          end

          def title(item)
            { type: :title, value: item[:title].to_s }
          end

          def class_def(data)
            { type: :class_def,
              name: data[:class_name].to_s,
              styles: data[:class_styles].to_s }
          end

          def node(data)
            { type: :node,
              indent: Text.of(data[:indent]).length,
              label: Text.of(data[:label][:string]) }
              .merge(optional(data))
          end

          def optional(data)
            extra = {}
            extra[:value] = data[:value].to_s.to_f if data.key?(:value)
            extra[:css_class] = data[:css_class].to_s if data.key?(:css_class)
            extra
          end
        end
      end
    end
  end
end
