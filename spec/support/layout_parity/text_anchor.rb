# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Where a <text> sits: x/y on the text, else on its first positioned
    # tspan, plus dx/dy of the text and that tspan. Non-numeric units (em)
    # count as 0: no font metrics.
    class TextAnchor
      POSITIONING = %w[x y dx dy].freeze
      LEADING_NUMBER = /\A\s*(#{Matrix::NUMBER})(?![a-z%])/

      def initialize(text)
        @text = text
        @tspan = text.element_children.find { |child| positioned?(child) }
      end

      def point
        [coordinate("x", "dx"), coordinate("y", "dy")]
      end

      private

      def positioned?(child)
        child.name == "tspan" &&
          child.attribute_nodes.map(&:name).intersect?(POSITIONING)
      end

      def coordinate(position, shift)
        first_number(@text[position] || tspan_attribute(position)) +
          first_number(@text[shift]) + first_number(tspan_attribute(shift))
      end

      def tspan_attribute(name)
        @tspan&.[](name)
      end

      def first_number(text)
        text.to_s[LEADING_NUMBER, 1].to_f
      end
    end
  end
end
