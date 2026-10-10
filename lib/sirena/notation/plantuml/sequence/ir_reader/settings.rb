# frozen_string_literal: true

require_relative "../appearance"
require_relative "../head_style"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        module IRReader
          # Rebuilds the footbox, the appearance and the banners.
          module Settings
            NUMBERS = %i[min_width tab_size max_message].freeze
            TEXTS = %i[tab_fill tab_colour].freeze
            HEAD_NUMBERS = %i[size].freeze
            HEAD_TEXTS = %i[colour style family weight line].freeze
            private_constant :NUMBERS, :TEXTS, :HEAD_NUMBERS, :HEAD_TEXTS

            module_function

            # @return [Hash] the Diagram keywords these settings fill
            def call(index)
              { appearance: appearance(index),
                footbox: index.with_role("no_footbox").empty?,
                warnings: index.with_role("warning").map(&:label).freeze }
            end

            def appearance(index)
              node = index.with_role("appearance").first
              alignment = index.detail(node, "alignment")&.to_sym
              Appearance.new(
                **read(node, index, NUMBERS, TEXTS, ""),
                alignment: alignment,
                head_style: HeadStyle.new(**head(node, index)),
              )
            end

            def head(node, index)
              read(node, index, HEAD_NUMBERS, HEAD_TEXTS, "head_")
            end

            def read(node, index, numbers, texts, prefix)
              (numbers + texts).to_h do |key|
                value = index.detail(node, "#{prefix}#{key}")
                value &&= value.to_i if numbers.include?(key)
                [key, value]
              end
            end
          end
        end
      end
    end
  end
end
