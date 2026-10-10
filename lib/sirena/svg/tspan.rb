# frozen_string_literal: true

require "lutaml/model"
require_relative "element"

module Sirena
  module Svg
    # SVG Tspan element <tspan>
    #
    # One styled run inside a <text> element: a bold or italic word, or the
    # start of a new line after a hard line break. Only the attributes a
    # markdown run actually needs — position resets (`x`, `y`) and per-run
    # styling (`font-weight`, `font-style`).
    #
    # `dy` is not an attribute: the :metanorma profile rejects it on a
    # tspan. A run starting a new line sets `line_shift` instead, and the
    # parent Text turns it into an absolute `y` (see Text#place_lines).
    # Everything else (font family/size, fill, text-anchor) is inherited
    # from the parent <text> element and never repeated here.
    class Tspan < Element
      attribute :x, :float
      attribute :y, :float
      # Lines below the previous placed run; never written to the SVG.
      attribute :line_shift, :integer
      attribute :font_weight, :string
      attribute :font_style, :string
      attribute :content, :string, collection: true

      writes_attributes :x, :y, :font_weight, :font_style

      protected

      # `content` is declared `collection: true`, so join rather than
      # interpolate.
      #
      # @return [String] XML string
      def element_markup
        escaped_content = Escaping.escape_text(Array(content).join)
        "<tspan#{build_attributes}>#{escaped_content}</tspan>"
      end
    end
  end
end
