# frozen_string_literal: true

module Sirena
  # ECMA-262's Number::toString, shared by every parser that has to draw a
  # YAML number exactly the way mermaid's JS runtime would print it. Two
  # sites (Parser::MetadataYaml and Source::Frontmatter) reimplemented this
  # independently before extraction; keep it in one place so a stringify
  # bugfix does not have to be applied twice.
  module JsNumber
    module_function

    # Every YAML number reaches JS as a double, and JS prints one in plain
    # decimal only while the point sits within 21 digits of the front and 6
    # of the back. Ruby switches to exponential far earlier, at 1e16, and
    # keeps a bignum exact that JS has already rounded. So `1e21` draws
    # "1e+21", `1e-5` draws "0.00001", and `9007199254740993` draws
    # "9007199254740992".
    def stringify(value)
      double = value.to_f
      return double.to_s unless double.finite?
      return '0' if double.zero?

      digits, point = decompose(double)
      text = place(digits, point)
      double.negative? ? "-#{text}" : text
    end

    # Ruby's Float#to_s already gives the shortest digits that round trip,
    # and they are the same ones JS uses — only where the point sits
    # differs. So this pulls the two apart and `place` puts them back
    # together the way JS does.
    def decompose(double)
      mantissa, _, exponent = double.abs.to_s.partition('e')
      whole, _, fraction = mantissa.partition('.')
      combined = whole + fraction
      digits = combined.sub(/\A0+/, '')
      point = whole.length - (combined.length - digits.length) +
              exponent.to_i
      [digits.sub(/0+\z/, ''), point]
    end
    private_class_method :decompose

    def place(digits, point)
      return exponential(digits, point) unless point > -6 && point <= 21
      return digits + ('0' * (point - digits.length)) if
        digits.length <= point
      return "0.#{'0' * -point}#{digits}" unless point.positive?

      "#{digits[0, point]}.#{digits[point..]}"
    end
    private_class_method :place

    def exponential(digits, point)
      power = point - 1
      head = digits.length == 1 ? digits : "#{digits[0]}.#{digits[1..]}"
      "#{head}e#{power.negative? ? '-' : '+'}#{power.abs}"
    end
    private_class_method :exponential
  end
end
