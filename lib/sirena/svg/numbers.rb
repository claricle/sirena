# frozen_string_literal: true

require_relative 'escaping'

module Sirena
  module Svg
    # Reading and writing the numbers that end up in SVG attributes.
    #
    # Three callers needed the same two things and each would have grown its
    # own version: turn whatever an attribute is holding into a Float, and
    # turn a computed Float back into an attribute value that does not read
    # as floating-point noise.
    #
    # `read` has to cope with more than Float(). lutaml-model leaves an unset
    # attribute holding a sentinel object rather than nil, renderers assign
    # opacities as strings, and a font size may carry a unit (`14px`). Any
    # value it cannot make sense of comes back nil, which every caller treats
    # as "not set" rather than as zero.
    module Numbers
      # A leading SVG number: optional sign, digits with an optional decimal
      # part, optional exponent. Anything after it (a `px` unit, whitespace)
      # is ignored rather than rejected.
      LEADING = /\A\s*[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?/

      # Computed coordinates are floats, so 67.0 + 14.0 * 0.35 lands on
      # 71.89999999999999 as often as on 71.9. Four decimals is finer than
      # any diagram needs and short enough to read in a diff.
      PRECISION = 4
      private_constant :LEADING, :PRECISION

      module_function

      # @param value [Object] an attribute value, or lutaml's unset sentinel
      # @return [Float, nil] the number it holds, or nil if it holds none
      def read(value)
        return nil if Escaping.blank?(value)
        return value.to_f if value.is_a?(Numeric)

        matched = value.to_s[LEADING]
        matched&.to_f
      end

      # @param value [Float] a computed number
      # @return [String] the attribute value to emit
      def write(value)
        value.round(PRECISION).to_s
      end
    end
  end
end
