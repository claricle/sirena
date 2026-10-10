# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        module IRReader
          # Rebuilds the items, in the order their nodes were emitted.
          module Items
            READERS = { "message" => Messages.method(:call),
                        "note" => Blocks.method(:note),
                        "ref" => Blocks.method(:ref),
                        "fragment" => Blocks.method(:fragment),
                        "divider" => Blocks.method(:divider),
                        "activation" => Blocks.method(:activation),
                        "destroy" => Blocks.method(:destroy),
                        "page_break" => Blocks.method(:page_break) }.freeze
            private_constant :READERS

            module_function

            def call(index)
              index.with_role(*READERS.keys).map do |node|
                READERS.fetch(node.role).call(node, index)
              end
            end
          end
        end
      end
    end
  end
end
