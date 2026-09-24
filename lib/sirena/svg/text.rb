# frozen_string_literal: true

require 'lutaml/model'
require_relative 'element'
require_relative 'numbers'
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

      # How far below `y` the baseline sits, in ems -- stands in for
      # `dominant-baseline` (rejected under :metanorma). Conventional
      # approximations, NOT font metrics: `central` is deliberately
      # collapsed onto `middle` since Sirena has none. An unnamed value
      # stays on the alphabetic baseline (deliberate for `mathematical`).
      #
      # Needs a unitless font size in user units; a relative size from
      # a foreign document (`2em`) has no parent to resolve against and
      # reads as the bare number.
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

      # `dx` and `dy` are folded into x/y rather than emitted, never written
      # out directly.
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

      protected

      # A text element carries content, so it is not the self-closing tag
      # the base class writes.
      #
      # `content` is declared `collection: true`. Renderers assign a plain
      # String, so join rather than interpolate — Array(content).join is a
      # no-op for a plain string and correct if content is ever multi-valued.
      # Content may hold newlines, so this is the one entry in #xml_lines
      # that is not a single line. It is why Group indents entries rather
      # than lines.
      #
      # Every renderer call site sets exactly one of `content`/`tspans`.
      #
      # @return [String] XML string
      def element_markup
        "<text#{build_attributes}>#{body}</text>"
      end

      def element_attributes
        attribute_pairs(ATTRIBUTE_PAIRS)
      end

      # SVG dx/dy are per-glyph offset lists. Their :float declarations make
      # lutaml keep only the leading number before this method sees the value.
      def offset_x
        offset = Numbers.read(dx)
        return x if offset.nil?

        computed_x = (Numbers.read(x) || 0.0) + offset
        return x unless computed_x.finite?

        Numbers.write(computed_x)
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

      # Every renderer call site sets exactly one of `content`/`tspans`.
      #
      # @return [String]
      def body
        Escaping.escape_text(Array(content).join) + Array(tspans).map(&:to_xml).join
      end

      # May be non-finite when the font size is: #baseline_y is the one place
      # that can fall back, so the check lives there rather than here too.
      #
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
