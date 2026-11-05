# frozen_string_literal: true

require_relative "network"
require_relative "timing"
require_relative "ebnf"

module Sirena
  module Notation
    module PlantUML
      # The plain-picture families that no other family's lines can be
      # mistaken for: network, timing and EBNF diagrams. Dispatched to from
      # {PlantUML.parse}, ahead of the families that read general lines.
      module Further
        extend self

        FAMILIES = [[Network, :network?], [Timing, :timing?],
                    [Ebnf, :ebnf?]].freeze
        private_constant :FAMILIES

        # @return [Boolean] whether one of the families claims the source
        def further?(source)
          !family_of(source).nil?
        end

        # @return [Notation::Parsed]
        def parse(source)
          family_of(source).first.parse(source)
        end

        private

        def family_of(source)
          FAMILIES.find { |klass, query| klass.public_send(query, source) }
        end
      end
    end
  end
end
