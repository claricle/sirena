# frozen_string_literal: true

require 'lutaml/model'
require_relative 'element'
require_relative 'numbers'

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

      # How far below `y` the baseline sits, in ems, for each
      # `dominant-baseline` value renderers set.
      #
      # SVG Tiny 1.2 has no `dominant-baseline`, so the svg_conform
      # :metanorma profile rejects it on `<text>`. Renderers set it to say
      # "centre this label on y" or "hang it below y", and that intent
      # survives the translation: the same shift applied to `y` puts the
      # baseline where the property would have put it, in a renderer that
      # supports the property and in one that does not.
      #
      # 0.35em is the usual centring constant — roughly half a cap height
      # above the baseline. `hanging` sits a full ascender below `y`;
      # `text-after-edge` a descender above it. Anything else, including
      # `auto` and `alphabetic`, already means "baseline at y".
      BASELINE_SHIFTS = {
        'middle' => 0.35,
        'central' => 0.35,
        'hanging' => 0.8,
        'text-before-edge' => 0.8,
        'text-after-edge' => -0.2,
        'ideographic' => -0.2
      }.freeze

      # The CSS initial font-size, used when a Text carries a baseline
      # request but no size of its own. Every renderer sets one; this keeps
      # a hand-built element from shifting by an arbitrary amount.
      DEFAULT_FONT_SIZE = 16.0

      # Written out rather than declared with .writes_attributes, because
      # `y` is not emitted from the `y` reader — see #baseline_y.
      ATTRIBUTE_PAIRS = [
        ['x', :x],
        ['y', :baseline_y],
        ['dx', :dx],
        ['dy', :dy],
        ['text-anchor', :text_anchor],
        ['font-family', :font_family],
        ['font-size', :font_size],
        ['font-weight', :font_weight],
        ['font-style', :font_style]
      ].map(&:freeze).freeze
      private_constant :ATTRIBUTE_PAIRS

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

      # Override to_xml to include text content.
      #
      # `content` is a collection because lutaml-model 0.8 requires that
      # under `mixed: true`. Renderers assign a plain String, but
      # `from_xml` yields an Array, so join rather than interpolate —
      # otherwise a parsed Text serializes as `<text>["plain"]</text>`.
      def to_xml
        attrs = build_attributes
        "<text#{attrs}>#{Escaping.escape_text(Array(content).join)}</text>"
      end

      protected

      def element_attributes
        attribute_pairs(ATTRIBUTE_PAIRS)
      end

      # `y` with the baseline request folded in.
      #
      # Returns the reader untouched when there is no shift, so a Text that
      # never asked for one serialises exactly as it did before.
      #
      # @return [Object, nil] the y attribute value
      def baseline_y
        shift = baseline_shift
        return y if shift.zero?

        Numbers.write((Numbers.read(y) || 0.0) + shift)
      end

      private

      # @return [Float] the baseline offset in user units
      def baseline_shift
        return 0.0 if Escaping.blank?(dominant_baseline)

        ems = BASELINE_SHIFTS.fetch(dominant_baseline.to_s.strip.downcase, 0.0)
        return 0.0 if ems.zero?

        ems * (Numbers.read(font_size) || DEFAULT_FONT_SIZE)
      end
    end
  end
end
