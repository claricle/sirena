# frozen_string_literal: true

module Sirena
  module Layout
    # sin and cos rounded correctly to the nearest double, whatever the
    # platform. The radial seed needs them identical everywhere: the system
    # libm differs from mmdc's browser in the last bit for a few percent of
    # arguments, and a symmetric mindmap amplifies one bit into visibly
    # different positions. The browser's own result is within 0.55 ulp of
    # the true value, so it equals the correctly rounded one for all but a
    # small fraction of arguments.
    module MindmapCoseTrig
      DIGITS = 60
      SCALE = 10**DIGITS
      PI = Rational("3.14159265358979323846264338327950288419716939937510582097494459230781640628620899")
      HALF_PI = PI / 2

      module_function

      # @param x [Float] angle in radians
      # @return [Float]
      def sin(x)
        quadrant, remainder = reduce(x)
        case quadrant
        when 0 then to_float(sine_series(remainder))
        when 1 then to_float(cosine_series(remainder))
        when 2 then to_float(-sine_series(remainder))
        else to_float(-cosine_series(remainder))
        end
      end

      # @param x [Float] angle in radians
      # @return [Float]
      def cos(x)
        quadrant, remainder = reduce(x)
        case quadrant
        when 0 then to_float(cosine_series(remainder))
        when 1 then to_float(-sine_series(remainder))
        when 2 then to_float(-cosine_series(remainder))
        else to_float(sine_series(remainder))
        end
      end

      # @return [Array] the quarter turns in x modulo four, and the rest as
      #   a SCALE-fixed integer within a quarter pi of zero
      def reduce(x)
        angle = Rational(x)
        turns = (angle / HALF_PI).round
        [turns % 4, ((angle - (turns * HALF_PI)) * SCALE).round]
      end

      def sine_series(fixed)
        series(fixed, fixed, 1)
      end

      def cosine_series(fixed)
        series(SCALE, fixed, 0)
      end

      # Sums a Taylor series in fixed point: each term is the previous one
      # times x squared over the next two factorial factors.
      def series(first_term, fixed, start)
        square = fixed * fixed / SCALE
        total = term = first_term
        index = start
        loop do
          term = -term * square / SCALE / ((index + 1) * (index + 2))
          break if term.zero?

          total += term
          index += 2
        end
        total
      end

      # Rounds a fixed-point value to the nearest double through the
      # decimal string, which Float() rounds correctly.
      def to_float(fixed)
        whole, fraction = fixed.abs.divmod(SCALE)
        sign = fixed.negative? ? "-" : ""
        Float("#{sign}#{whole}.#{fraction.to_s.rjust(DIGITS, '0')}")
      end
    end
  end
end
