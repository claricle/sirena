# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # A `box "title" ... endbox` grouping of neighbouring participants.
        # `members` are participant ids; `title` is the source text; `fill` is
        # the {Fill} written after the title, or nil.
        class Box
          attr_reader :title, :members, :fill

          def initialize(title:, members:, fill: nil)
            @title = title
            @members = members.freeze
            @fill = fill
            freeze
          end
        end
      end
    end
  end
end
