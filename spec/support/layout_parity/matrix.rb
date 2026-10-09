# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # A 2D affine transform in SVG's (a b c d e f) order.
    class Matrix
      NUMBER = /[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?/

      BUILDERS = {
        "translate" => :from_translate,
        "scale" => :from_scale,
        "rotate" => :from_rotate,
        "matrix" => :from_matrix,
      }.freeze

      attr_reader :a, :b, :c, :d, :e, :f

      def self.identity
        new([1, 0, 0, 1, 0, 0])
      end

      def self.translate(shift_x, shift_y = 0.0)
        new([1, 0, 0, 1, shift_x, shift_y])
      end

      def self.scale(factor_x, factor_y = factor_x)
        new([factor_x, 0, 0, factor_y, 0, 0])
      end

      def self.rotate(degrees, center_x = 0.0, center_y = 0.0)
        turn = rotation(degrees * Math::PI / 180)
        translate(center_x, center_y) * turn * translate(-center_x, -center_y)
      end

      def self.rotation(radians)
        cosine = Math.cos(radians)
        sine = Math.sin(radians)
        new([cosine, sine, -sine, cosine, 0, 0])
      end

      # Parses an SVG transform list. Only translate, scale, rotate and matrix
      # exist in the contract; anything else raises rather than being ignored.
      def self.parse(text)
        calls = text.to_s.scan(/(\w+)\s*\(([^)]*)\)/)
        calls.reduce(identity) do |total, (name, args)|
          total * from_function(name, args.scan(NUMBER).map(&:to_f))
        end
      end

      def self.from_function(name, numbers)
        builder = BUILDERS.fetch(name) do
          raise ArgumentError, "unsupported transform function: #{name}"
        end
        send(builder, numbers)
      end

      def self.from_translate(numbers)
        translate(numbers.fetch(0), numbers.fetch(1, 0.0))
      end

      def self.from_scale(numbers)
        scale(numbers.fetch(0), numbers.fetch(1, numbers.fetch(0)))
      end

      def self.from_rotate(numbers)
        rotate(numbers.fetch(0), numbers.fetch(1, 0.0), numbers.fetch(2, 0.0))
      end

      def self.from_matrix(numbers)
        return new(numbers) if numbers.size == 6

        raise ArgumentError, "matrix needs six numbers"
      end

      def initialize(values)
        @a, @b, @c, @d, @e, @f = values.map(&:to_f)
      end

      # self * other applies other first, then self.
      def *(other)
        first = linear(other.a, other.b)
        second = linear(other.c, other.d)
        Matrix.new([*first, *second, *apply(other.e, other.f)])
      end

      def apply(x_pos, y_pos)
        moved_x, moved_y = linear(x_pos, y_pos)
        [moved_x + e, moved_y + f]
      end

      def to_a
        [a, b, c, d, e, f]
      end

      private

      def linear(x_pos, y_pos)
        [(a * x_pos) + (c * y_pos), (b * x_pos) + (d * y_pos)]
      end
    end
  end
end
