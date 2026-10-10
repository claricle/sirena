# frozen_string_literal: true

require_relative "../caption"
require_relative "../style_sheet"

module Sirena
  module Notation
    module PlantUML
      module IRReader
        # Rebuilds the captions, the style sheet and the directives.
        module Annotations
          module_function

          # @return [Array<Caption>]
          def captions(index)
            index.with_role(*Caption::KINDS.map(&:to_s)).map do |node|
              Caption.new(node.role.to_sym, node.label)
            end
          end

          # @return [Array<String>]
          def directives(index)
            index.with_role("directive").map(&:label)
          end

          # @return [StyleSheet]
          def style(index)
            node = index.with_role("style").first
            return StyleSheet.new unless node

            StyleSheet.new(background: index.detail(node, "background"),
                           rules: rules(node, index))
          end

          def rules(style, index)
            index.children(style, "style_rule").to_h do |node|
              [node.label.to_sym, rule(node, index)]
            end
          end

          def rule(node, index)
            index.children(node, "background", "colour", "size").to_h do |item|
              value = item.label
              [item.role.to_sym, item.role == "size" ? value.to_i : value]
            end
          end
        end
      end
    end
  end
end
