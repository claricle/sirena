# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # `create X`: the next message to X makes its head appear at that
        # row instead of at the top of the diagram.
        class Create
          # @param items [Array] a diagram's items
          # @return [Hash{Message => String}] each message that creates a
          #   participant, with that participant's id
          def self.messages(items)
            pending = nil
            items.each_with_object({}.compare_by_identity) do |item, found|
              pending = item.participant if item.is_a?(Create)
              next unless item.is_a?(Message) && pending == item.to

              found[item] = pending
              pending = nil
            end
          end

          attr_reader :participant

          def initialize(participant:)
            @participant = participant
            freeze
          end
        end
      end
    end
  end
end
