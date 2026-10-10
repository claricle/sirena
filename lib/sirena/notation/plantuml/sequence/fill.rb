# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # The colour written after a participant: `#RGB`, `#RRGGBB`,
        # `#RRGGBBAA` or `#transparent`. PlantUML draws a fully transparent
        # one as no fill, and keeps any other alpha as a fill opacity.
        class Fill
          PATTERN = /\#(\h{8}|\h{6}|\h{3}|transparent)(?!\w)/i
          OPAQUE = 255
          NONE = "none"

          attr_reader :colour, :opacity

          # @return [Fill, nil] nil when the token is not one of the forms
          def self.read(token)
            digits = token&.match(PATTERN)&.[](1)
            return unless digits

            digits.casecmp?("transparent") ? new(NONE) : from_hex(digits)
          end

          def self.from_hex(digits)
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
