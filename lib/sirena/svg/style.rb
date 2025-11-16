# frozen_string_literal: true

require 'lutaml/model'

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

      # Convert style to CSS string for inline style attribute
      #
      # @return [String] CSS style string
      def to_css
        properties = []
        properties << "fill:#{fill}" if fill
        properties << "stroke:#{stroke}" if stroke
        properties << "stroke-width:#{stroke_width}" if stroke_width
        properties << "stroke-dasharray:#{stroke_dasharray}" if stroke_dasharray
        properties << "opacity:#{opacity}" if opacity
        properties << "fill-opacity:#{fill_opacity}" if fill_opacity
        properties << "stroke-opacity:#{stroke_opacity}" if stroke_opacity
        properties << "font-family:#{font_family}" if font_family
        properties << "font-size:#{font_size}" if font_size
        properties << "font-weight:#{font_weight}" if font_weight
        properties << "text-anchor:#{text_anchor}" if text_anchor
        properties.join(';')
      end
    end
  end
end
