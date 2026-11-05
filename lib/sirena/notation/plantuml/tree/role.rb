# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Tree
        # What a tree node carries beyond its text, spelled as the node's IR
        # role: the side of its parent it hangs on, whether it draws no box,
        # and the fill a style class gave it. `left_boxless_bg_lightgreen`
        # reads back as all three.
        class Role
          PATTERN = /\A(left|right)(_boxless)?(?:_bg_([0-9a-z]+))?\z/
          HEX = /\A(?:\h{6}|\h{3})\z/
          private_constant :PATTERN, :HEX

          attr_reader :side, :fill

          # @param role [String, nil] an IR node role
          # @return [Role]
          def self.parse(role)
            match = PATTERN.match(role.to_s)
            return new("right", false, nil) unless match

            new(match[1], !match[2].nil?, fill_of(match[3]))
          end

          # A fill is a CSS colour name or three or six hex digits; a role
          # token cannot hold the `#`.
          def self.fill_of(token)
            return unless token

            token.match?(HEX) ? "##{token}" : token
          end
          private_class_method :fill_of

          # @return [String] the role token for the parts
          def self.spell(side:, boxless: false, fill: nil)
            token = side.dup
            token << "_boxless" if boxless
            token << "_bg_#{fill.delete_prefix('#').downcase}" if fill
            token
          end

          def initialize(side, boxless, fill)
            @side = side
            @boxless = boxless
            @fill = fill
          end

          def boxless
            @boxless
          end
        end
      end
    end
  end
end
