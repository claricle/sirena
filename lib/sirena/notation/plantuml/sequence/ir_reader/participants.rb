# frozen_string_literal: true

require_relative "../box"
require_relative "../participant"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        module IRReader
          # Rebuilds the lifelines and the boxes round them.
          module Participants
            KINDS = %w[participant actor boundary control entity database
                       collections queue].freeze
            private_constant :KINDS

            module_function

            def participants(index)
              index.with_role(*KINDS).map do |node|
                Participant.new(
                  id: index.detail(node, "name"), label: node.label,
                  kind: node.role.to_sym,
                  stereotype: index.detail(node, "stereotype"),
                  fill: Fills.call(node, index)
                )
              end
            end

            def boxes(index)
              index.with_role("box").map do |node|
                Box.new(title: node.label,
                        members: index.target_names(node))
              end
            end
          end
        end
      end
    end
  end
end
