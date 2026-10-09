# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # One lifeline. `id` is what messages name; `label` is the text drawn
        # on its head, as written.
        class Participant
          attr_reader :id, :label, :kind

          def initialize(id:, label: id, kind: :participant)
            @id = id
            @label = label
            @kind = kind
            freeze
          end
        end
      end
    end
  end
end
