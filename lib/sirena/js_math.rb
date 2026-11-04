# frozen_string_literal: true

module Sirena
  # The transcendental functions of JavaScript's Math, correctly rounded:
  # the double nearest the true value, the same on every OS and in every
  # sirena runtime. The platform libm (glibc, Apple libm, the wasm build's
  # own) differs from the others in the last bit for a few percent of
  # arguments, and a layout amplifies one bit into a visible shift.
  # Current V8 (Chrome 156, measured over 30000 random inputs per function)
  # returns the correctly rounded value for sin, cos, atan, atan2, log and
  # log10 too, so this is also the closest match to what mermaid draws.
  # (V8's older fdlibm port is NOT the target: it differs from the correctly
  # rounded value for 1-3% of arguments, and from itself between x86 and
  # arm64 because the compiler fuses multiply-adds on arm64.)
  #
  # Everything is exact integer arithmetic in 256-bit fixed point, so the
  # Rust port in sirena-rs (crates/sirena-core/src/js_math.rs) computes the
  # identical bits step for step. Keep the two in step. hypot is V8's own
  # algorithm (builtins/math.tq), which is plain IEEE arithmetic. sqrt is
  # IEEE-exact everywhere and stays Math.sqrt.
  module JsMath
    BITS = 256
    ONE = 1 << BITS
    WIDE_BITS = 1400
    TWO_POW_20 = 2.0**20
    SQRT_HALF = 0.7071067811865476

    module_function

    # @return [Float] sin(x) as JS Math.sin
    def sin(value)
      value = Float(value)
      return Float::NAN if value.nan? || value.infinite?
      return value if value.abs < 2.0**-27

      trig(value, 0)
    end

    # @return [Float] cos(x) as JS Math.cos
    def cos(value)
      value = Float(value)
      return Float::NAN if value.nan? || value.infinite?
      return 1.0 if value.abs < 2.0**-27

      trig(value, 1)
    end

    # @return [Float] atan(x) as JS Math.atan
    def atan(value)
      value = Float(value)
      return value if value.nan? || value.zero?

      negative = value.negative?
      magnitude = value.abs
      result =
        if magnitude < 2.0**-26 then magnitude
        else to_float(atan_fixed(to_fixed(magnitude)), -BITS)
        end
      negative ? -result : result
    end

    # @return [Float] atan2(y, x) as JS Math.atan2
    def atan2(ordinate, abscissa)
      ordinate = Float(ordinate)
      abscissa = Float(abscissa)
      return Float::NAN if ordinate.nan? || abscissa.nan?
      if atan2_special?(ordinate, abscissa)
        return atan2_special(ordinate, abscissa)
      end

      ratio = fraction_of(ordinate.abs, abscissa.abs)
      sign_of(ordinate) * atan2_angle(ratio, abscissa.negative?)
    end

    # Math.hypot is not libm in V8: it scales by the largest magnitude and
    # sums the squares with Kahan compensation (builtins/math.tq).
    # @return [Float] sqrt of the sum of squares
    def hypot(*values)
      return 0.0 if values.empty?

      values = values.map { |value| Float(value) }
      magnitudes = values.map(&:abs)
      max = largest_magnitude(magnitudes)
      special = hypot_special(values, max)
      return special if special

      Math.sqrt(kahan_squares(magnitudes, max)) * max
    end

    def largest_magnitude(magnitudes)
      magnitudes.reject(&:nan?).max || 0.0
    end

    # nil when the scaled Kahan sum is needed.
    def hypot_special(values, max)
      return Float::INFINITY if max.eql?(Float::INFINITY)
      return Float::NAN if values.any?(&:nan?)

      0.0 if max.zero?
    end

    def kahan_squares(magnitudes, max)
      sum = 0.0
      compensation = 0.0
      magnitudes.each do |value|
        ratio = value / max
        summand = (ratio * ratio) - compensation
        preliminary = sum + summand
        compensation = (preliminary - sum) - summand
        sum = preliminary
      end
      sum
    end

    # @return [Float] natural logarithm as JS Math.log
    def log(value)
      value = Float(value)
      special = log_special(value)
      return special if special

      to_float(ln_fixed(value), -BITS)
    end

    # @return [Float] base-10 logarithm as JS Math.log10
    def log10(value)
      value = Float(value)
      special = log_special(value)
      return special if special

      to_float(fixed_div(ln_fixed(value), ln10_fixed), -BITS)
    end

    # nil when value is an ordinary positive number.
    def log_special(value)
      return Float::NAN if value.nan? || value.negative?
      return -Float::INFINITY if value.zero?
      return value if value.infinite?

      0.0 if (value - 1.0).zero?
    end

    # @return [Float] base ** exponent as JS Math.pow (**)
    def pow(base, exponent)
      base = Float(base)
      exponent = Float(exponent)
      return 1.0 if exponent.zero?
      return Float::NAN if pow_nan?(base, exponent)
      return pow_special(base, exponent) if pow_special?(base, exponent)

      pow_finite(base, exponent)
    end

    def pow_nan?(base, exponent)
      return true if base.nan? || exponent.nan?

      exponent.infinite? && (base.abs - 1.0).zero?
    end

    def pow_special?(base, exponent)
      base.zero? || base.infinite? || exponent.infinite?
    end

    def pow_finite(base, exponent)
      return -pow(-base, exponent) if base.negative? && odd_integer?(exponent)
      return Float::NAN if base.negative? && exponent.to_i != exponent

      pow_positive(base.abs, exponent)
    end

    # --- fixed point: an Integer n stands for n / 2**BITS ---------------

    def to_fixed(value, bits = BITS)
      return 0 if value.zero?

      fixed = scaled_mantissa(value.abs, bits)
      value.negative? ? -fixed : fixed
    end

    def scaled_mantissa(magnitude, bits)
      mantissa, exponent = split_double(magnitude)
      shift = exponent + bits
      shift.negative? ? mantissa >> -shift : mantissa << shift
    end

    # Product, truncated toward zero.
    def fixed_mul(left, right)
      product = left * right
      product.negative? ? -(-product >> BITS) : product >> BITS
    end

    # Truncating division, as Rust's.
    def idiv(numerator, divisor)
      numerator.negative? ? -(-numerator / divisor) : numerator / divisor
    end

    def fixed_div(left, right)
      idiv(left << BITS, right)
    end

    # The nearest double to fixed * 2**exponent, ties to even.
    def to_float(fixed, exponent)
      return 0.0 if fixed.zero?
      return -to_float(-fixed, exponent) if fixed.negative?

      excess = fixed.bit_length - 53
      if excess.positive?
        fixed, exponent = round_to_double(fixed, excess, exponent)
      end
      Math.ldexp(fixed.to_f, exponent)
    end

    def round_to_double(fixed, excess, exponent)
      kept = fixed >> excess
      rest = fixed - (kept << excess)
      half = 1 << (excess - 1)
      kept += 1 if rest > half || (rest == half && kept.odd?)
      [kept, exponent + excess]
    end

    def sqrt_fixed(fixed)
      Integer.sqrt(fixed << BITS)
    end

    # sum of term / divisor over odd divisors; each term is the previous
    # times sign * square (series in small**2).
    def odd_series(first, square, sign)
      term = first
      sum = 0
      divisor = 1
      until term.zero?
        sum += idiv(term, divisor)
        term = sign * fixed_mul(term, square)
        divisor += 2
      end
      sum
    end

    def atan_series(small)
      odd_series(small, fixed_mul(small, small), -1)
    end

    # atan of a fixed value in [0, 1], by three argument halvings.
    def atan_unit(value)
      3.times do
        value = fixed_div(value,
                          ONE + sqrt_fixed(ONE + fixed_mul(value, value)))
      end
      atan_series(value) << 3
    end

    def atan_fixed(value)
      return -atan_fixed(-value) if value.negative?
      return atan_unit(value) if value <= ONE

      (pi_fixed >> 1) - atan_unit(fixed_div(ONE, value))
    end

    # atan for |x| < 2**-27, where t - t**3/3 + t**5/5 settles it exactly.
    def atan_tiny(magnitude)
      atan_tiny_fraction(*fraction_of(magnitude, 1.0))
    end

    def atan_tiny_fraction(num, den)
      num2 = num * num
      den2 = den * den
      poly = (15 * den2 * den2) - (5 * num2 * den2) + (3 * num2 * num2)
      integer_ratio_to_float(num * poly, 15 * (den**5))
    end

    # The nearest double to numerator / denominator (both positive).
    def integer_ratio_to_float(numerator, denominator)
      shift = denominator.bit_length + 60 - numerator.bit_length
      top, bottom = align_ratio(numerator, denominator, shift)
      scaled, rest = top.divmod(bottom)
      to_float((scaled << 1) | (rest.zero? ? 0 : 1), -shift - 1)
    end

    def align_ratio(numerator, denominator, shift)
      return [numerator << shift, denominator] if shift.positive?

      [numerator, denominator << -shift]
    end

    # y / x as an exact integer pair [numerator, denominator].
    def fraction_of(top, bottom)
      top_num, top_exp = split_double(top)
      bottom_num, bottom_exp = split_double(bottom)
      shift = top_exp - bottom_exp
      return [top_num, bottom_num << -shift] if shift.negative?

      [top_num << shift, bottom_num]
    end

    def split_double(value)
      fraction, exponent = Math.frexp(value)
      [(fraction * (2.0**53)).to_i, exponent - 53]
    end

    def atan_ratio(ratio)
      num, den = ratio
      return atan_tiny_fraction(num, den) if (num << 27) < den

      to_float(atan_ratio_fixed(ratio), -BITS)
    end

    def atan_ratio_fixed(ratio)
      atan_fixed((ratio[0] << BITS) / ratio[1])
    end

    def sign_of(value)
      value.to_s.start_with?("-") ? -1 : 1
    end

    def positive_zero?(value)
      value.zero? && sign_of(value).positive?
    end

    def atan2_special?(ordinate, abscissa)
      [ordinate, abscissa].any? { |value| value.zero? || value.infinite? }
    end

    def atan2_angle(ratio, left_half)
      return atan_ratio(ratio) unless left_half

      to_float(pi_fixed - atan_ratio_fixed(ratio), -BITS)
    end

    def atan2_special(ordinate, abscissa)
      return atan2_zero_ordinate(ordinate, abscissa) if ordinate.zero?
      return sign_of(ordinate) * pi_float / 2 if abscissa.zero?

      atan2_infinite(ordinate, abscissa)
    end

    def atan2_zero_ordinate(ordinate, abscissa)
      return ordinate if abscissa.positive? || positive_zero?(abscissa)

      sign_of(ordinate) * pi_float
    end

    def atan2_infinite(ordinate, abscissa)
      sign = sign_of(ordinate)
      return sign * infinite_ordinate_angle(abscissa) if ordinate.infinite?

      abscissa.positive? ? sign * 0.0 : sign * pi_float
    end

    def infinite_ordinate_angle(abscissa)
      return pi_float / 2 unless abscissa.infinite?

      abscissa.positive? ? pi_float / 4 : 3.0 * (pi_float / 4)
    end

    def pi_float
      @pi_float ||= to_float(pi_fixed, -BITS)
    end

    # Machin: pi = 16 atan(1/5) - 4 atan(1/239), at +64 guard bits.
    def pi_bits(bits)
      @pi_bits ||= {}
      @pi_bits[bits] ||= machin_pi(bits + 64) >> 64
    end

    def machin_pi(work)
      (16 * arctan_inverse(5, work)) - (4 * arctan_inverse(239, work))
    end

    # sum over k of block.call(1/(d**(2k+1)(2k+1)), k), in work-bit fixed point.
    def inverse_power_sum(divisor, work)
      power = (1 << work) / divisor
      square = divisor * divisor
      sum = 0
      index = 0
      until power.zero?
        sum += yield(power / ((2 * index) + 1), index)
        power /= square
        index += 1
      end
      sum
    end

    def arctan_inverse(divisor, work)
      inverse_power_sum(divisor, work) { |term, k| k.even? ? term : -term }
    end

    def pi_fixed
      pi_bits(BITS)
    end

    def atanh_inverse(divisor)
      inverse_power_sum(divisor, BITS + 64) { |term, _index| term }
    end

    def ln2_fixed
      @ln2_fixed ||= (2 * atanh_inverse(3)) >> 64
    end

    def ln10_fixed
      @ln10_fixed ||= ((6 * atanh_inverse(3)) + (2 * atanh_inverse(9))) >> 64
    end

    # ln(value) for finite value > 0, as a fixed value.
    def ln_fixed(value)
      fraction, exponent = Math.frexp(value)
      if fraction < SQRT_HALF
        fraction *= 2.0
        exponent -= 1
      end
      mantissa = to_fixed(fraction)
      ratio = fixed_div(mantissa - ONE, mantissa + ONE)
      series = odd_series(ratio, fixed_mul(ratio, ratio), 1)
      (exponent * ln2_fixed) + (series << 1)
    end

    # exp of a fixed value, as [fixed mantissa, binary exponent].
    def exp_fixed(value)
      steps = ((value << 1) + ln2_fixed).div(ln2_fixed << 1)
      sum = exp_series((value - (steps * ln2_fixed)) >> 8)
      8.times { sum = fixed_mul(sum, sum) }
      [sum, steps]
    end

    def exp_series(reduced)
      term = ONE
      sum = ONE
      index = 1
      until term.zero?
        term = idiv(fixed_mul(term, reduced), index)
        sum += term
        index += 1
      end
      sum
    end

    def pow_positive(base, exponent)
      power = fixed_mul(ln_fixed(base), to_fixed(exponent))
      return Float::INFINITY if power > 710 * ONE
      return 0.0 if power < -746 * ONE

      mantissa, steps = exp_fixed(power)
      to_float(mantissa, steps - BITS)
    end

    def odd_integer?(value)
      value.abs < 2.0**53 && value == value.to_i && value.to_i.odd?
    end

    def pow_special(base, exponent)
      return pow_infinite_exponent(base, exponent) if exponent.infinite?

      huge = base.zero? ? exponent.negative? : exponent.positive?
      value = huge ? Float::INFINITY : 0.0
      negative_odd_base?(base, exponent) ? -value : value
    end

    def pow_infinite_exponent(base, exponent)
      return Float::INFINITY if (base.abs > 1.0) == exponent.positive?

      0.0
    end

    def negative_odd_base?(base, exponent)
      negative = base.zero? ? (1.0 / base).negative? : base.negative?
      negative && odd_integer?(exponent)
    end

    SIN_TABLE = [[:sine, 1], [:cosine, 1], [:sine, -1], [:cosine, -1]].freeze
    COS_TABLE = [[:cosine, 1], [:sine, -1], [:cosine, -1], [:sine, 1]].freeze

    # sin (kind 0) or cos (kind 1) of a double with |value| >= 2**-27.
    def trig(value, kind)
      bits = value.abs < TWO_POW_20 ? BITS : WIDE_BITS
      turns, remainder = reduce_quadrant(value, bits)
      function, sign = (kind.zero? ? SIN_TABLE : COS_TABLE)[turns % 4]
      to_float(sign * trig_series(function, remainder), -BITS)
    end

    def trig_series(function, remainder)
      return sine_series(remainder) if function == :sine

      cosine_series(remainder)
    end

    def reduce_quadrant(value, bits)
      pio2 = pi_bits(bits) >> 1
      wide = to_fixed(value, bits)
      turns = ((wide << 1) + pio2).div(pio2 << 1)
      [turns, (wide - (turns * pio2)) >> (bits - BITS)]
    end

    def sine_series(small)
      square = fixed_mul(small, small)
      term = small
      sum = 0
      index = 1
      until term.zero?
        sum += term
        term = idiv(-fixed_mul(term, square), (index + 1) * (index + 2))
        index += 2
      end
      sum
    end

    def cosine_series(small)
      square = fixed_mul(small, small)
      term = ONE
      sum = 0
      index = 0
      until term.zero?
        sum += term
        term = idiv(-fixed_mul(term, square), (index + 1) * (index + 2))
        index += 2
      end
      sum
    end
  end
end
