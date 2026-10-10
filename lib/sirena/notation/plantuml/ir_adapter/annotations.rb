# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module IRAdapter
        # Encodes what surrounds the classes: captions, the style sheet and
        # the directives the parser recorded.
        module Annotations
          module_function

          def call(diagram, sink)
            diagram.captions.each do |caption|
              sink.node(caption.kind.to_s, caption.text)
            end
            style(diagram.style, sink)
            diagram.directives.each { |text| sink.node("directive", text) }
          end

          # @param style [StyleSheet] encoded only when it sets something
          def style(style, sink)
            rules = style.rules
            return if style.background.nil? && rules.empty?

            node = sink.node("style")
            sink.detail(node, "background", style.background)
            rules.each { |kind, rule| style_rule(kind, rule, node, sink) }
          end

          def style_rule(kind, rule, parent, sink)
            node = sink.node("style_rule", kind.to_s, parent: parent)
            rule.each do |property, value|
              sink.detail(node, property.to_s, value)
            end
          end
        end
      end
    end
  end
end
