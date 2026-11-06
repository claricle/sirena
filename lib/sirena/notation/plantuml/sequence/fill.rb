# frozen_string_literal: true

require_relative "../style/colour_names"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # The colour written after a participant: `#RGB`, `#RRGGBB`,
        # `#RRGGBBAA`, `#transparent` or a CSS colour name.
        # PlantUML draws a fully transparent one as no fill, and keeps any
        # other alpha as a fill opacity.
        class Fill
          PATTERN = /\#(\h{8}|\h{6}|\h{3}|transparent|[a-z]+)(?!\w)/i
          OPAQUE = 255
          NONE = "none"

          attr_reader :colour, :opacity

          # @return [Fill, nil] nil when the token is not one of the forms
          def self.read(token)
            digits = token&.match(PATTERN)&.[](1)
            return unless digits
            return new(NONE) if digits.casecmp?("transparent")

            from_hex(digits) || named(digits)
          end

          def self.named(name)
            hex = PlantUML::Style::ColourNames::TABLE[name.downcase]
            new(hex) if hex
          end
          private_class_method :named

          def self.from_hex(digits)
            return unless digits.match?(/\A\h{3}(?:\h{3}|\h{5})?\z/)

            full = digits.length == 3 ? digits.gsub(/./) { |c| c * 2 } : digits
            alpha = full.length == 8 ? full[6, 2].hex : OPAQUE
            return new(NONE) if alpha.zero?

            new("##{full[0, 6].upcase}", alpha == OPAQUE ? nil : alpha)
          end
          private_class_method :from_hex

          # @param alpha [Integer, nil] 1..254, or nil for an opaque colour
          def initialize(colour, alpha = nil)
            @colour = colour
            @opacity = alpha && (alpha / 255.0).round(5)
            freeze
          end
        end
      end
    end
  end
end
