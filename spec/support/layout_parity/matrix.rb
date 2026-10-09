# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # A 2D affine transform in SVG's (a b c d e f) order.
    class Matrix
      NUMBER = /[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?/

      attr_reader :a, :b, :c, :d, :e, :f

      def self.identity
        new(1, 0, 0, 1, 0, 0)
      end

      def initialize(a, b, c, d, e, f)
        @a = a.to_f
        @b = b.to_f
        @c = c.to_f
        @d = d.to_f
        @e = e.to_f
        @f = f.to_f
      end

      def self.translate(tx, ty = 0.0)
        new(1, 0, 0, 1, tx, ty)
      end

      def self.scale(sx, sy = sx)
        new(sx, 0, 0, sy, 0, 0)
      end

      def self.rotate(degrees, cx = 0.0, cy = 0.0)
        r = degrees * Math::PI / 180
        rotation = new(Math.cos(r), Math.sin(r), -Math.sin(r), Math.cos(r), 0, 0)
        translate(cx, cy) * rotation * translate(-cx, -cy)
      end

      # Parses an SVG transform list. Only translate, scale, rotate and matrix
      # exist in the contract; anything else raises rather than being ignored.
      def self.parse(text)
        text.to_s.scan(/(\w+)\s*\(([^)]*)\)/).reduce(identity) do |total, (name, args)|
          total * from_function(name, args.scan(NUMBER).map(&:to_f))
        end
      end

      def self.from_function(name, n)
        case name
        when "translate" then translate(n.fetch(0), n.fetch(1, 0.0))
        when "scale" then scale(n.fetch(0), n.fetch(1, n.fetch(0)))
        when "rotate" then rotate(n.fetch(0), n.fetch(1, 0.0), n.fetch(2, 0.0))
        when "matrix" then n.size == 6 ? new(*n) : raise(ArgumentError, "matrix needs six numbers")
        else raise ArgumentError, "unsupported transform function: #{name}"
        end
      end

      # self * other applies other first, then self.
      def *(other)
        Matrix.new(a * other.a + c * other.b, b * other.a + d * other.b,
                   a * other.c + c * other.d, b * other.c + d * other.d,
                   a * other.e + c * other.f + e, b * other.e + d * other.f + f)
      end

      def apply(x, y)
        [a * x + c * y + e, b * x + d * y + f]
      end

      def to_a
        [a, b, c, d, e, f]
      end
    end
  end
end
