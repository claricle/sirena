# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # One lifeline. `id` is what messages name; `label` is the text drawn
        # on its head, as written; `stereotype` is the text of a `<<...>>`
        # after the declaration.
        class Participant
          attr_reader :id, :label, :kind, :stereotype, :fill

          # @param fill [Fill, nil] the colour written after the declaration
          def initialize(id:, label: id, kind: :participant, stereotype: nil,
                         fill: nil)
            @id = id
            @label = label
            @kind = kind
            @stereotype = stereotype
            @fill = fill
            freeze
          end
        end
      end
    end
  end
end
