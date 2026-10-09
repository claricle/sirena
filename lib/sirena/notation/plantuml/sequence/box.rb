# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # A `box "title" ... endbox` grouping of neighbouring participants.
        # `members` are participant ids; `title` is the source text.
        class Box
          attr_reader :title, :members

          def initialize(title:, members:)
            @title = title
            @members = members.freeze
            freeze
          end
        end
      end
    end
  end
end
