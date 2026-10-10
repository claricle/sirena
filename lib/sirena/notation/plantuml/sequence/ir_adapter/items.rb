# frozen_string_literal: true

require_relative "../activation"
require_relative "../destroy"
require_relative "../divider"
require_relative "../fragment"
require_relative "../message"
require_relative "../note"
require_relative "../page_break"
require_relative "../ref"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        module IRAdapter
          # Encodes the items of the diagram, in source order.
          module Items
            ENCODERS = [[Message, Messages.method(:call)],
                        [Note, Blocks.method(:note)],
                        [Ref, Blocks.method(:ref)],
                        [Fragment, Blocks.method(:fragment)],
                        [Divider, Blocks.method(:divider)],
                        [Activation, Blocks.method(:activation)],
                        [Destroy, Blocks.method(:destroy)],
                        [PageBreak, Blocks.method(:page_break)]].freeze
            private_constant :ENCODERS

            module_function

            def call(diagram, sink, ids)
              diagram.items.each do |item|
                encoder = ENCODERS.find { |type, _| item.is_a?(type) }
                encoder.last.call(item, sink, ids)
              end
            end
          end
        end
      end
    end
  end
end
