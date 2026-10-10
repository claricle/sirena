# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # The header, footer, caption and legend written around a sequence
        # diagram. Each text is its lines joined by "\n"; `legend_place` is
        # "<top|bottom> <left|center|right>".
        class Chrome
          DEFAULT_PLACE = "bottom center"
          KINDS = %i[header footer caption legend].freeze

          # @param texts [Hash{Symbol => String}] a text per kind in KINDS
          # @param legend_place [String, nil]
          def initialize(texts = {}, legend_place: nil)
            @texts = texts.slice(*KINDS).freeze
            @legend_place = legend_place || DEFAULT_PLACE
            freeze
          end

          NONE = new

          attr_reader :legend_place

          # @return [String, nil]
          def text(kind)
            @texts[kind]
          end

          # @return [Array<String>] the lines of one kind, empty if unset
          def lines(kind)
            @texts.fetch(kind, "").split("\n")
          end

          # @return [Hash{Symbol => String}]
          def to_h
            @texts
          end

          # @return [Symbol] :top or :bottom
          def legend_edge
            legend_place.split.first.to_sym
          end

          # @return [Symbol] :left, :center or :right
          def legend_side
            legend_place.split.last.to_sym
          end

          # @param kind [Symbol] one of KINDS
          # @return [Chrome] this chrome with one more text
          def with(kind, text, place = legend_place)
            Chrome.new(@texts.merge(kind => text), legend_place: place)
          end
        end
      end
    end
  end
end
