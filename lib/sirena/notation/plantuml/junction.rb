# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # An association class: `(from, to) .. owner`. The `owner` class hangs
      # off the relation between `from` and `to`.
      class Junction
        attr_reader :from, :to, :owner

        def initialize(from:, to:, owner:)
          @from = from
          @to = to
          @owner = owner
          freeze
        end
      end
    end
  end
end
