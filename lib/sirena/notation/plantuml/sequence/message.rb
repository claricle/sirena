# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # One arrow, normalised so `from` is always the sender: `B <- A` and
        # `A -> B` read the same. `head` is :filled for `->` and :open for
        # `->>`; `dashed` is true for `-->`. `label` is the source text.
        class Message
          attr_reader :from, :to, :label, :head, :dashed

          def initialize(from:, to:, label:, head:, dashed:)
            @from = from
            @to = to
            @label = label
            @head = head
            @dashed = dashed
            freeze
          end

          def self_message?
            from == to
          end
        end
      end
    end
  end
end
