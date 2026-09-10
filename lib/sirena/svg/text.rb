# frozen_string_literal: true

require 'lutaml/model'
require_relative 'element'
require_relative 'tspan'

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
      attribute :content, :string, collection: true
      attribute :tspans, Tspan, collection: true

      writes_attributes :x, :y, :dx, :dy, :text_anchor, :font_family, :font_size, :font_weight, :font_style, :dominant_baseline

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
        map_element 'tspan', to: :tspans
      end

      # Override to_xml to include text content.
      #
      # `content` is a collection because lutaml-model 0.8 requires that
      # under `mixed: true`. Renderers assign a plain String, but
      # `from_xml` yields an Array, so join rather than interpolate —
      # otherwise a parsed Text serializes as `<text>["plain"]</text>`.
      #
      # Every renderer call site sets exactly one of `content`/`tspans`, but
      # `from_xml` populates both independently from ordinary mixed SVG
      # content (`<text>foo<tspan>bar</tspan></text>`), so `body` has to
      # decide how to put them back together — see it for how true
      # interleaving is preserved rather than assumed away.
      def to_xml
        "<text#{build_attributes}>#{body}</text>"
      end

      private

      # `content` and `tspans` are separate collections with no ordering
      # between them, but genuinely interleaved mixed content
      # (`<text>A<tspan>B</tspan>C</text>`) needs one. lutaml-model already
      # records that order during `from_xml`: `element_order` (from
      # `Lutaml::Xml::XmlOrderable`, mixed in via `Serializable`) holds one
      # entry per text run and per child element, in source sequence — it's
      # what `Transformation#should_use_element_order?` itself checks for
      # before trusting it. A renderer-constructed instance never sets it
      # (confirmed: `Svg::Text.new.tap { |t| t.content = "x" }.element_order`
      # is `nil`), so every existing call site — which sets exactly one of
      # `content`/`tspans` — falls straight to the simple path unchanged.
      #
      # @return [String]
      def body
        return interleaved_body if element_order && !element_order.empty?

        Escaping.escape_text(Array(content).join) + Array(tspans).map(&:to_xml).join
      end

      # Replays `element_order` in place: each text node's own content in
      # sequence, each element node standing in for the next parsed
      # `<tspan>` — `tspans` is themselves already in document order, so
      # consuming it as a queue lines each one up with the element_order
      # entry it came from.
      #
      # @return [String]
      def interleaved_body
        remaining_tspans = Array(tspans).dup

        element_order.map do |node|
          if node.node_type == :text
            Escaping.escape_text(node.text_content)
          else
            remaining_tspans.shift.to_xml
          end
        end.join
      end
    end
  end
end
