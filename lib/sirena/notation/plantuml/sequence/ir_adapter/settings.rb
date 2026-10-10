# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        module IRAdapter
          # Encodes what applies to the whole diagram: the footbox, the
          # appearance skinparam and `<style>` set, the banners and the title.
          module Settings
            KEYS = %i[min_width alignment tab_fill tab_colour tab_size
                      max_message].freeze
            HEAD_KEYS = %i[colour size style family weight line].freeze
            private_constant :KEYS, :HEAD_KEYS

            module_function

            def call(diagram, sink)
              sink.node("no_footbox") unless diagram.footbox?
              appearance(diagram.appearance, sink)
              diagram.warnings.each { |line| sink.node("warning", line) }
              sink.node("title", diagram.title) if diagram.title
            end

            def appearance(appearance, sink)
              node = sink.node("appearance")
              KEYS.each do |key|
                sink.detail(node, key.to_s, appearance.public_send(key))
              end
              head = appearance.head_style
              HEAD_KEYS.each do |key|
                sink.detail(node, "head_#{key}", head.public_send(key))
              end
            end
          end
        end
      end
    end
  end
end
