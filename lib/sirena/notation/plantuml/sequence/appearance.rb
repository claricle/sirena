# frozen_string_literal: true

require_relative "head_style"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # What skinparam and `<style>` set for a sequence diagram: the
        # narrowest participant head, how a head's lines sit against each
        # other, the {HeadStyle} of the heads, and the fill, text colour and
        # text size of a fragment's keyword tab.
        # A setting the source never made is nil, except `alignment` and
        # `head_style`.
        class Appearance
          KEYS = %i[min_width alignment tab_fill tab_colour tab_size
                    head_style].freeze
          private_constant :KEYS

          attr_reader :min_width, :tab_fill, :tab_colour, :tab_size

          def initialize(**settings)
            unknown = settings.keys - KEYS
            raise ArgumentError, "unknown: #{unknown}" if unknown.any?

            @settings = settings.freeze
            @min_width, @tab_fill, @tab_colour, @tab_size =
              settings.values_at(:min_width, :tab_fill, :tab_colour, :tab_size)
            freeze
          end

          # @return [Symbol] :left, :center or :right
          def alignment
            @settings[:alignment] || :center
          end

          # @return [HeadStyle]
          def head_style
            @settings[:head_style] || HeadStyle.new
          end

          # @return [Appearance] this one with each setting `other` made
          def merge(other)
            Appearance.new(
              **@settings.merge(other.made) { |_, mine, new| new || mine },
              head_style: head_style.merge(other.head_style),
            )
          end

          protected

          # The settings the source made, without the defaults.
          def made
            @settings.compact
          end
        end
      end
    end
  end
end
