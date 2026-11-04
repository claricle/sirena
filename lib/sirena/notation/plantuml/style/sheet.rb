# frozen_string_literal: true

require_relative "defaults"

module Sirena
  module Notation
    module PlantUML
      module Style
        # What a diagram's source says about its look, in the order PlantUML
        # applies it: the defaults, then `skinparam`, then `<style>`, then
        # the colours written on one element. A later layer wins; inside a
        # layer the element's own rule wins over the global one, and a
        # stereotype rule over both.
        class Sheet
          LAYERS = %i[skin style].freeze
          private_constant :LAYERS

          # @param skin [Hash{String => Hash}] skinparam rules by selector
          # @param style [Hash{String => Hash}] `<style>` rules by selector
          # @param elements [Hash{String => Hash}] properties by element id
          def initialize(skin: {}, style: {}, elements: {})
            @layers = { skin: skin, style: style }
            @elements = elements
            freeze
          end

          # @param id [String] an element id, as the family reader names it
          # @param properties [Hash] the properties written on that element
          # @return [Sheet] this sheet with the element's properties added
          def with_element(id, properties)
            merged = @elements.merge(id => properties) do |_, old, new|
              old.merge(new)
            end
            self.class.new(skin: @layers[:skin], style: @layers[:style],
                           elements: merged)
          end

          # @param element [Symbol] :state, :class, :activity, :note, :arrow
          # @param property [Symbol] :background, :border, :font_colour,
          #   :font_name, :font_size, :line_style, :round_corner,
          #   :line_thickness
          # @param id [String, nil] the element's id, for its own colours
          # @param stereotype [String, nil] the element's stereotype
          # @return [Object, nil] the winning value, nil when none is set
          def resolve(element, property, id: nil, stereotype: nil)
            explicit(element, property, id: id, stereotype: stereotype) ||
              from_defaults(element, property).compact.last
          end

          # Like {#resolve}, but nil when the source itself sets nothing, for
          # a renderer whose own default look is not PlantUML's.
          def explicit(element, property, id: nil, stereotype: nil)
            candidates(element, property, id, stereotype).compact.last
          end

          # @param id [String] an element id
          # @return [Hash] the properties written on that element
          def element(id)
            @elements.fetch(id, {})
          end

          # @return [Boolean] whether any layer above the defaults is set
          def styled?
            @layers.values.any? { |rules| !rules.empty? } ||
              !@elements.empty?
          end

          private

          def candidates(element, property, id, stereotype)
            LAYERS.flat_map do |layer|
              from_rules(@layers[layer], element, property, stereotype)
            end + [@elements.dig(id, property)]
          end

          def from_defaults(element, property)
            rules = Defaults::RULES
            [rules.dig(:any, property), rules.dig(element, property)]
          end

          def from_rules(rules, element, property, stereotype)
            selectors(element, stereotype).map do |selector|
              rules.dig(selector, property)
            end
          end

          def selectors(element, stereotype)
            [Style.selector(:any), Style.selector(element),
             (Style.selector(element, stereotype) if stereotype),
             (Style.selector(nil, stereotype) if stereotype)].compact
          end
        end
      end
    end
  end
end
