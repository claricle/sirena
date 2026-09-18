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
        map_attribute 'fill-opacity', to: :fill_opacity
        map_attribute 'stroke-opacity', to: :stroke_opacity
        map_attribute 'dominant-baseline', to: :dominant_baseline

        map_content to: :content
        map_element 'tspan', to: :tspans
      end

      protected

      # A text element carries content, so it is not the self-closing tag
      # the base class writes.
      #
      # `content` is a collection because lutaml-model 0.8 requires that
      # under `mixed: true`. Renderers assign a plain String, but
      # `from_xml` yields an Array, so join rather than interpolate —
      # otherwise a parsed Text serializes as `<text>["plain"]</text>`.
      # Content may hold newlines, so this is the one entry in #xml_lines
      # that is not a single line. It is why Group indents entries rather
      # than lines.
      #
      # Every renderer call site sets exactly one of `content`/`tspans`, but
      # `from_xml` populates both independently from ordinary mixed SVG
      # content (`<text>foo<tspan>bar</tspan></text>`), so `body` has to
      # decide how to put them back together — see it for how true
      # interleaving is preserved rather than assumed away.
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

      # `content` and `tspans` are separate collections with no ordering
      # between them, but genuinely interleaved mixed content
      # (`<text>A<tspan>B</tspan>C</text>`) needs one — `element_order`
      # (from `Lutaml::Xml::XmlOrderable`) holds it, one entry per text run
      # and child element, in source sequence, set only by `from_xml`. A
      # renderer-constructed instance never sets it, so every existing call
      # site (sets exactly one of `content`/`tspans`) falls to the simple
      # path unchanged.
      #
      # @return [String]
      def body
        return interleaved_body if element_order && !element_order.empty?

        simple_body
      end

      # The `element_order`-free path above, and the fallback `interleaved_body`
      # uses when `content`/`tspans` no longer match the shape `element_order`
      # recorded (see the cardinality check there).
      #
      # @return [String]
      def simple_body
        Escaping.escape_text(Array(content).join) + Array(tspans).map(&:to_xml).join
      end

      # Replays `element_order` in place: each `:text` entry stands in for
      # the next item of `content`, each `tspan` `:element` entry for the
      # next item of `tspans` — both queues already in document order.
      # Reads from those queues, not `node.text_content` directly, so a
      # later `content =` reassignment is honored. An entry that is
      # neither `:text` nor a `tspan` is skipped, not treated as a
      # stand-in for the next tspan. Relies on `cardinality_matches?`
      # first — see its comment for why a caller reassigning to a
      # different count must not replay this mapping.
      #
      # @return [String]
      def interleaved_body
        return simple_body unless cardinality_matches?

        remaining_tspans = Array(tspans).dup
        remaining_content = Array(content).dup

        element_order.filter_map do |node|
          case node.node_type
          when :text
            Escaping.escape_text(remaining_content.shift.to_s)
          when :element
            remaining_tspans.shift&.to_xml if node.name == 'tspan'
          end
        end.join
      end

      # True when `content`/`tspans`' current sizes still match what
      # `element_order` recorded at parse time. A caller that reassigns to
      # a DIFFERENT count (e.g. `.content = %w[X Y Z]` onto only 2 recorded
      # `:text` slots) makes a naive `element_order` replay silently drop
      # the extra items instead of erroring — `interleaved_body` falls back
      # to `simple_body` instead when this returns false.
      #
      # @return [Boolean]
      def cardinality_matches?
        text_slots = element_order.count { |node| node.node_type == :text }
        tspan_slots = element_order.count { |node| node.node_type == :element && node.name == 'tspan' }

        Array(content).size == text_slots && Array(tspans).size == tspan_slots
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
