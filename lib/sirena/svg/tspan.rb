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

      protected

      # `content` is declared `collection: true`, so join rather than
      # interpolate.
      #
      # @return [String] XML string
      def element_markup
        "<tspan#{build_attributes}>#{Escaping.escape_text(Array(content).join)}</tspan>"
      end
    end
  end
end
