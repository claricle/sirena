# frozen_string_literal: true

require_relative "../activation"
require_relative "../destroy"
require_relative "../divider"
require_relative "../fragment"
require_relative "../note"
require_relative "../page_break"
require_relative "../ref"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        module IRReader
          # Rebuilds every item that is not a message.
          module Blocks
            module_function

            def note(node, index)
              Note.new(shape: index.detail(node, "shape").to_sym,
                       side: index.detail(node, "side").to_sym,
                       targets: index.target_names(node), text: node.label,
                       parallel: !index.detail(node, "parallel").nil?,
                       fill: Fills.call(node, index))
            end

            def ref(node, index)
              Ref.new(targets: index.target_names(node), label: node.label)
            end

            def fragment(node, index)
              Fragment.new(phase: index.detail(node, "phase").to_sym,
                           keyword: index.detail(node, "keyword"),
                           label: node.label,
                           parallel: !index.detail(node, "parallel").nil?)
            end

            def divider(node, _index)
              Divider.new(label: node.label)
            end

            def activation(node, index)
              Activation.new(participant: index.target_names(node).first,
                             phase: index.detail(node, "phase").to_sym,
                             color: index.detail(node, "colour"))
            end

            def destroy(node, index)
              Destroy.new(participant: index.target_names(node).first)
            end

            def page_break(_node, _index)
              PageBreak.new
            end
          end
        end
      end
    end
  end
end
