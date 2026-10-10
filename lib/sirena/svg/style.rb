# frozen_string_literal: true

require "lutaml/model"

module Sirena
  module Svg
    # Represents CSS styling for SVG elements
    #
    # Encapsulates style properties that can be applied to SVG elements
    # as inline styles or style attributes.
    class Style < Lutaml::Model::Serializable
      attribute :fill, :string
      attribute :stroke, :string
      attribute :stroke_width, :float
      attribute :stroke_dasharray, :string
      attribute :opacity, :float
      attribute :fill_opacity, :float
      attribute :stroke_opacity, :float
      attribute :font_family, :string
      attribute :font_size, :float
      attribute :font_weight, :string
      attribute :text_anchor, :string

      CSS_PROPERTIES = {
        fill: "fill",
        stroke: "stroke",
        stroke_width: "stroke-width",
        stroke_dasharray: "stroke-dasharray",
        opacity: "opacity",
        fill_opacity: "fill-opacity",
        stroke_opacity: "stroke-opacity",
        font_family: "font-family",
        font_size: "font-size",
        font_weight: "font-weight",
        text_anchor: "text-anchor",
      }.freeze
      private_constant :CSS_PROPERTIES

      # Convert style to CSS string for inline style attribute
      #
      # @return [String] CSS style string
      def to_css
        CSS_PROPERTIES.filter_map do |attribute, property|
          value = public_send(attribute)
          "#{property}:#{value}" if value
        end.join(";")
      end
    end
  end
end
