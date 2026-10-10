# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # Fills in the optional keywords of a constructor that would otherwise
        # take more than five parameters, and refuses a keyword it does not
        # know, as a real keyword list would.
        module KeywordDefaults
          # @param given [Hash{Symbol => Object}] the keywords the caller sent
          # @param defaults [Hash{Symbol => Object}] each optional keyword
          #   with its default
          # @return [Hash{Symbol => Object}] defaults overridden by given
          # @raise [ArgumentError] when given holds a keyword not in defaults
          def self.resolve(given, defaults)
            unknown = given.keys - defaults.keys
            unless unknown.empty?
              raise ArgumentError, "unknown keyword: #{unknown.first.inspect}"
            end

            defaults.merge(given)
          end
        end
      end
    end
  end
end
