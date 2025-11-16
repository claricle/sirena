# frozen_string_literal: true

require 'lutaml/model'
require_relative 'element'

module Sirena
  module Svg
    # SVG Text element <text>
    #
    # Displays text content at specified coordinates with optional styling
    # and anchoring. Used for labels, annotations, and textual content.
    class Text < Element
      attribute :x, :float
      attribute :y, :float
      attribute :dx, :float
      attribute :dy, :float
      attribute :text_anchor, :string
      attribute :font_family, :string
      attribute :font_size, :string
      attribute :font_weight, :string
      attribute :font_style, :string
      attribute :dominant_baseline, :string
      attribute :content, :string

      xml do
        root 'text', mixed: true
        map_attribute 'id', to: :id
        map_attribute 'class', to: :class_name
        map_attribute 'x', to: :x
        map_attribute 'y', to: :y
        map_attribute 'dx', to: :dx
        map_attribute 'dy', to: :dy
        map_attribute 'text-anchor', to: :text_anchor
        map_attribute 'font-family', to: :font_family
        map_attribute 'font-size', to: :font_size
        map_attribute 'font-weight', to: :font_weight
        map_attribute 'font-style', to: :font_style
        map_attribute 'fill', to: :fill
        map_attribute 'stroke', to: :stroke
        map_attribute 'stroke-width', to: :stroke_width
        map_attribute 'transform', to: :transform
        map_attribute 'opacity', to: :opacity
        map_attribute 'dominant-baseline', to: :dominant_baseline

        map_content to: :content
      end

      # Override to_xml to include text content
      def to_xml
        attrs = build_attributes
        "<text#{attrs}>#{content}</text>"
      end

      protected

      def element_attributes
        attrs = []
        attrs << %( x="#{x}") if x
        attrs << %( y="#{y}") if y
        attrs << %( dx="#{dx}") if dx
        attrs << %( dy="#{dy}") if dy
        attrs << %( text-anchor="#{text_anchor}") if text_anchor
        attrs << %( font-family="#{font_family}") if font_family
        attrs << %( font-size="#{font_size}") if font_size
        attrs << %( font-weight="#{font_weight}") if font_weight
        attrs << %( font-style="#{font_style}") if font_style
        attrs << %( dominant-baseline="#{dominant_baseline}") if dominant_baseline
        attrs
      end
    end
  end
end
