# frozen_string_literal: true

require 'lutaml/model'
require_relative 'element'

module Sirena
  module Svg
    # SVG Tspan element <tspan>
    #
    # One styled run inside a <text> element: a bold or italic word, or the
    # start of a new line after a hard line break. Only the attributes a
    # markdown run actually needs — position resets (`x`), vertical line
    # shifts (`dy`), and per-run styling (`font-weight`, `font-style`).
    # Everything else (font family/size, fill, text-anchor) is inherited
    # from the parent <text> element and never repeated here.
    class Tspan < Element
      attribute :x, :float
      attribute :dy, :string
      attribute :font_weight, :string
      attribute :font_style, :string
      attribute :content, :string, collection: true

      writes_attributes :x, :dy, :font_weight, :font_style

      xml do
        root 'tspan', mixed: true
        map_attribute 'id', to: :id
        map_attribute 'class', to: :class_name
        map_attribute 'x', to: :x
        map_attribute 'dy', to: :dy
        map_attribute 'font-weight', to: :font_weight
        map_attribute 'font-style', to: :font_style
        map_attribute 'fill', to: :fill

        map_content to: :content
      end

      # Override to_xml to include text content, mirroring Text#to_xml:
      # `content` is a collection because lutaml-model 0.8 requires that
      # under `mixed: true`, so join rather than interpolate.
      def to_xml
        attrs = build_attributes
        "<tspan#{attrs}>#{Escaping.escape_text(Array(content).join)}</tspan>"
      end
    end
  end
end
