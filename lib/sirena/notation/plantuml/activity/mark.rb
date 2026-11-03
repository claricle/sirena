# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Activity
        # One thing the renderer draws, in final coordinates.
        class Mark
          # @return [Symbol] :rect, :circle, :polygon, :path or :text
          attr_reader :kind
          # @return [Hash{Symbol => Object}] the attributes for that kind
          attr_reader :attrs

          def initialize(kind, **attrs)
            @kind = kind
            @attrs = attrs.freeze
            freeze
          end
        end
      end
    end
  end
end
