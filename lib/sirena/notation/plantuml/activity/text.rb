# frozen_string_literal: true

require_relative "../unsupported_construct_error"

module Sirena
  module Notation
    module PlantUML
      module Activity
        # Turns PlantUML label markup into plain lines. Creole styling is
        # dropped and a `<math>` formula is kept as its source; an embedded
        # image or sprite is refused, never dropped.
        module Text
          module_function

          TAG = %r{</?(?:b|i|u|s|w|plain|back|size|color|font)
                   (?:[:\s][^>]*)?>}xi
          PICTURE = /<(?:img|\$|&)/i
          FORMULA = %r{<(math|latex)>(.*?)</\1>}
          private_constant :TAG, :PICTURE, :FORMULA

          # @param raw [String]
          # @param line [Integer] source line, for the refusal
          # @return [String] lines joined by newlines
          def clean(raw, line:)
            if PICTURE.match?(raw)
              raise UnsupportedConstructError.new(construct: "image",
                                                  line: line, text: raw)
            end

            raw.gsub("\\n", "\n").gsub(FORMULA, '\2').gsub(TAG, "")
              .gsub(/\*\*|__/, "").split("\n").map(&:strip).join("\n").strip
          end
        end
      end
    end
  end
end
