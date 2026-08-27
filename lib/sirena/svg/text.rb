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

      # How far below `y` the baseline sits, in ems, for each value this map
      # approximates. Renderers set only `middle`, `hanging` and `auto`;
      # `central`, `text-before-edge`, `text-after-edge` and `ideographic`
      # are reachable only through `from_xml`.
      #
      # SVG Tiny 1.2 has no `dominant-baseline`, so the svg_conform
      # :metanorma profile rejects it on `<text>`. Renderers set it to say
      # "centre this label on y" or "hang it below y", and that intent
      # survives the translation: the same shift applied to `y` puts the
      # baseline where the property would have put it, in a renderer that
      # supports the property and in one that does not.
      #
      # These are the conventional em approximations, not measurements. A
      # real translation reads the font's baseline table — `middle` is half
      # an x-height, and the edge baselines come from ascent and descent —
      # and Sirena has no font metrics at all; TextMeasurement approximates
      # width by character count. `central` is the midpoint of ascent and
      # descent (~0.5em), while `middle` is half the x-height (~0.35em); Sirena
      # deliberately collapses them because it has no font metrics to separate
      # them.
      #
      # So 0.35em stands in for half an x-height,
      # `hanging` for a full ascender below `y`, `text-after-edge` for a
      # descender above it. Any value the map does not name is left on the
      # alphabetic baseline. For `mathematical`, that is a deliberate
      # approximation rather than a claim that its baseline coincides with
      # the alphabetic one. Contextual values such as `use-script`,
      # `no-change` and `reset-size` cannot be resolved here either.
      #
      # `middle`, `hanging` and `auto` are all reachable: radar.rb picks
      # between them per axis label by angle.
      #
      # The shift is in ems, so it needs a font size in user units. Every
      # renderer writes one unitless, which is what Numbers.read expects; a
      # relative size parsed in from a foreign document (`2em`) would be read
      # as the bare number, since there is no parent size to resolve against.
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
      private_constant :BASELINE_SHIFTS, :DEFAULT_FONT_SIZE

      # `dx` and `dy` are folded into x/y rather than emitted. They stay in the
      # xml block below, which is what `from_xml` reads: a parsed offset is
      # honoured the same way a set one is.
      #
      # Written out rather than declared with .writes_attributes, because
      # `x` and `y` are emitted from computed readers — see #offset_x and
      # #baseline_y.
      ATTRIBUTE_PAIRS = [
        ['x', :offset_x],
        ['y', :baseline_y],
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

      # SVG dx/dy are per-glyph offset lists. Numbers.read uses the leading
      # number, the same approximation the baseline shifts already make.
      def offset_x
        offset = Numbers.read(dx)
        return x if offset.nil?

        Numbers.write((Numbers.read(x) || 0.0) + offset)
      end

      # `y` with the baseline request folded in.
      #
      # Returns the reader untouched when there is no shift, so a Text that
      # never asked for one serialises exactly as it did before. It is also
      # the only usable fallback when the computed coordinate overflows.
      #
      # @return [Object, nil] the y attribute value
      def baseline_y
        shift = baseline_shift
        offset = Numbers.read(dy)
        return y if shift.zero? && offset.nil?

        computed_y = (Numbers.read(y) || 0.0) + (offset || 0.0) + shift
        return y unless computed_y.finite?

        Numbers.write(computed_y)
      end

      private

      # @return [Float] the baseline offset in user units
      def baseline_shift
        return 0.0 if Escaping.blank?(dominant_baseline)

        ems = BASELINE_SHIFTS.fetch(dominant_baseline.to_s.strip.downcase, 0.0)
        return 0.0 if ems.zero?

        shift = ems * (Numbers.read(font_size) || DEFAULT_FONT_SIZE)
        return 0.0 unless shift.finite?

        shift
      end
    end
  end
end
