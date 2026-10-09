# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # Reads the one `<style>` block the slice draws:
        # `sequenceDiagram { participant { MinimumWidth N } }`, optionally with
        # `HorizontalAlignment center`, which is the default. Any other block
        # is not read, so the parser refuses it instead of ignoring it.
        module Style
          extend self

          BLOCK = /\AsequenceDiagram\s*\{\s*participant\s*\{(.*)\}\s*\}\z/mi
          PROPERTY = /(\w+)[ \t]+(\S+)/
          private_constant :BLOCK, :PROPERTY

          # @param text [String] what lies between `<style>` and `</style>`
          # @return [Integer, nil] the minimum participant width, or nil when
          #   the block sets anything else
          def minimum_width(text)
            body = BLOCK.match(text.strip)&.[](1) or return
            properties = body.scan(PROPERTY).to_h { |k, v| [k.downcase, v] }
            return unless supported?(properties)

            Integer(properties.fetch("minimumwidth"), 10, exception: false)
          end

          private

          def supported?(properties)
            alignment = properties.fetch("horizontalalignment", "center")
            alignment.casecmp?("center") &&
              properties.except("horizontalalignment").keys == ["minimumwidth"]
          end
        end
      end
    end
  end
end
