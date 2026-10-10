# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # What a `participant { ... }` style block sets on the heads:
        # `colour` and `size` of the label, its `style`, `family` and
        # `weight`, and the `line` colour round the head. Each is nil until
        # the source sets it.
        class HeadStyle
          KEYS = %i[colour size style family weight line].freeze
          private_constant :KEYS

          attr_reader(*KEYS)

          def initialize(**settings)
            unknown = settings.keys - KEYS
            raise ArgumentError, "unknown: #{unknown}" if unknown.any?

            KEYS.each { |key| instance_variable_set(:"@#{key}", settings[key]) }
            freeze
          end

          # @return [HeadStyle] this one with each setting `other` made
          def merge(other)
            HeadStyle.new(**KEYS.to_h { |key| [key, other.pick(key, self)] })
          end

          def empty?
            KEYS.all? { |key| public_send(key).nil? }
          end

          protected

          def pick(key, fallback)
            public_send(key) || fallback.public_send(key)
          end
        end
      end
    end
  end
end
