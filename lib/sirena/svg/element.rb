# frozen_string_literal: true

require_relative 'escaping'
require 'lutaml/model'
require_relative 'numbers'
require_relative 'style'

module Sirena
  module Svg
    # Base class for all SVG elements.
    #
    # Provides common attributes and functionality shared by all SVG elements
    # including styling, transformation, and identification.
    class Element < Lutaml::Model::Serializable
      attribute :id, :string
      attribute :class_name, :string
      attribute :style, Svg::Style
      attribute :transform, :string
      attribute :fill, :string
      attribute :fill_opacity, :string
      attribute :stroke, :string
      attribute :stroke_width, :string
      attribute :stroke_opacity, :string
      attribute :opacity, :float

      # class_name is the only reader whose SVG name is not just its own
      # with underscores hyphenated.
      ATTRIBUTE_NAMES = { class_name: 'class' }.freeze
      private_constant :ATTRIBUTE_NAMES

      # The SVG name for a Ruby attribute reader.
      #
      # @param name [Symbol] the reader
      # @return [String] the attribute name to emit
      def self.svg_name(name)
        ATTRIBUTE_NAMES.fetch(name) { name.to_s.tr('_', '-') }
      end
      private_class_method :svg_name

      # Emitted by every element, in this order, as [svg name, reader].
      # Named once here rather than on every render.
      #
      # `opacity` is not in the list even though it is an attribute. SVG Tiny
      # 1.2 — the element and attribute table the svg_conform :metanorma
      # profile enforces — has no `opacity` property, only `fill-opacity` and
      # `stroke-opacity`. So the two opacity readers below fold it in rather
      # than emitting it, and every element inherits that by construction.
      BASE_PAIRS = [
        [svg_name(:id), :id],
        [svg_name(:class_name), :class_name],
        [svg_name(:transform), :transform],
        [svg_name(:fill), :fill],
        [svg_name(:fill_opacity), :painted_fill_opacity],
        [svg_name(:stroke), :stroke],
        [svg_name(:stroke_width), :stroke_width],
        [svg_name(:stroke_opacity), :painted_stroke_opacity]
      ].map(&:freeze).freeze
      private_constant :BASE_PAIRS

      # Generate XML representation of this element.
      #
      # A fragment, not a document. An element that draws sibling shapes — a
      # Path with an arrowhead — returns more than one root, and a strict
      # parser will refuse that as having two roots. Group and Document, the
      # only callers, join fragments, so that is the contract they already
      # rely on.
      #
      # @return [String] one or more sibling elements, newline separated
      def to_xml
        xml_lines.join("\n")
      end

      # Declares the attributes an element writes, in output order.
      #
      # Several subclasses were each carrying the same shape of method — a list of
      # names paired with the matching reader. Declaring them removes that
      # repetition and, more usefully, removes the chance of one class's
      # version drifting into a different shape.
      #
      # Ruby names map to SVG names by turning underscores into hyphens, which
      # covers every attribute these elements emit (`stroke_dasharray` becomes
      # `stroke-dasharray`). A notation needing anything else should override
      # #element_attributes rather than bend this.
      #
      # @param names [Array<Symbol>] attribute readers, in output order
      # @return [void]
      def self.writes_attributes(*names)
        pairs = names.map { |name| [svg_name(name), name].freeze }.freeze
        define_method(:element_attributes) { attribute_pairs(pairs) }

        # define_method defines a public method, while the base hook is
        # protected. Without this a declared subclass widened the API for no
        # reason and disagreed with its own parent.
        protected :element_attributes
      end

      protected

      # The complete markup for one element.
      #
      # @return [String] XML string
      def element_markup
        tag = self.class.name.split('::').last.downcase
        attrs = build_attributes

        "<#{tag}#{attrs}/>"
      end

      # The markup a parent indents, one entry per structural unit.
      #
      # Separate from #to_xml because a parent may not indent every line of a
      # child's markup: a Text holding a newline would have its content
      # rewritten. Group indents entries instead, and Text#element_markup is
      # the only entry that may carry a newline of its own.
      #
      # @return [Array<String>] this element's markup, then each sibling's
      def xml_lines
        [element_markup, *sibling_markup]
      end

      # Hook for subclasses to draw sibling shapes alongside this element.
      #
      # @return [Array<String>] one entry of markup per sibling
      def sibling_markup
        []
      end

      # Build attribute string for XML output
      #
      # @return [String] formatted attribute string
      def build_attributes
        Escaping.attributes(attribute_pairs(BASE_PAIRS) + element_attributes)
      end

      # Reads the current values for already-named attributes.
      #
      # Shared with .writes_attributes so the base attributes and a
      # subclass's own go through one naming rule. Written out as literal
      # pairs in both places, the hyphenation was typed by hand here and
      # computed there, which is two spellings of one rule.
      #
      # `send`, not `public_send`: some pair-table readers are protected:
      # #painted_fill_opacity and #painted_stroke_opacity here, plus
      # Text#offset_x and Text#baseline_y in the subclass. `public_send`
      # cannot reach them.
      #
      # @param pairs [Array<Array>] [svg name, reader], in output order
      # @return [Array<Array>] name/value pairs
      def attribute_pairs(pairs)
        pairs.map { |svg_name, reader| [svg_name, send(reader)] }
      end

      # `fill-opacity` as it should be painted, with any whole-element
      # `opacity` folded in.
      #
      # @return [Object, nil] the attribute value, or nil when unset
      def painted_fill_opacity
        composed_opacity(fill_opacity)
      end

      # `stroke-opacity` as it should be painted, with any whole-element
      # `opacity` folded in.
      #
      # @return [Object, nil] the attribute value, or nil when unset
      def painted_stroke_opacity
        composed_opacity(stroke_opacity)
      end

      private

      # Multiplies a component opacity by the whole-element one.
      #
      # The translation is exact where a shape paints only one of fill and
      # stroke. Where a stroke overlaps its own fill, the overlap is painted
      # darker: `1 - (1 - a)^2` instead of `a`. SVG Tiny 1.2 has no object
      # opacity, so no exact translation exists and this is the deviation
      # Sirena accepts. It is confined to the inner half of a shape's own
      # outline; the shipped examples reach it on stroked, filled, translucent
      # rects such as the quadrant background.
      #
      # On a container they are NOT equivalent, and this makes no attempt to
      # be. Group opacity composites the group as one rendered surface, while
      # these two are inherited paint properties: a child setting its own
      # `fill-opacity` replaces the group's rather than multiplying by it,
      # and overlapping children composite differently. Nothing sets
      # `opacity` on a Group, so nothing Sirena emits takes that path — the
      # six sites set it on leaf shapes: a Path, three Rects, a Text and an
      # Arrowhead Polygon.
      #
      # A component value that is not a number is left exactly as it was.
      # Non-finite operands also leave the component alone because Float::NAN
      # cannot be clamped and an invalid attribute must not make the document
      # fail to serialize. Nothing in the gem writes either kind, and
      # inventing a factor for one would emit a number the caller never asked
      # for.
      #
      # @param component [Object] fill-opacity or stroke-opacity as set
      # @return [Object, nil] the value to emit
      def composed_opacity(component)
        whole = Numbers.read(opacity)
        return component if whole.nil?

        part = Escaping.blank?(component) ? 1.0 : Numbers.read(component)
        return component if part.nil?
        return component unless whole.finite? && part.finite?

        whole = whole.clamp(0.0, 1.0)
        part = part.clamp(0.0, 1.0)
        Numbers.write(part * whole)
      end

      protected

      # Hook for subclasses to add their specific attributes.
      #
      # Returns name/value PAIRS, not rendered markup. That is deliberate: it
      # leaves Escaping.attributes as the only code that turns an attribute
      # into text, so a subclass cannot emit an unescaped one. Pairs with a
      # nil value are dropped, so callers need no conditionals.
      #
      # @return [Array<Array>] name/value pairs
      def element_attributes
        []
      end
    end
  end
end
