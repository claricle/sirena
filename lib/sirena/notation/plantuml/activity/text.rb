# frozen_string_literal: true

require_relative "../unsupported_construct_error"

module Sirena
  module Notation
    module PlantUML
      module Activity
        # Turns PlantUML label markup into plain lines. Creole styling is
        # dropped; an embedded image or sprite is refused, never dropped.
        module Text
          module_function

          TAG = %r{</?(?:b|i|u|s|w|plain|back|size|color|font)
                   (?:[:\s][^>]*)?>}xi
          PICTURE = /<(?:img|\$|&)/i
          private_constant :TAG, :PICTURE

          # @param raw [String]
          # @param line [Integer] source line, for the refusal
          # @return [String] lines joined by newlines
          def clean(raw, line:)
            if PICTURE.match?(raw)
              raise UnsupportedConstructError.new(construct: "image",
                                                  line: line, text: raw)
            end

            raw.gsub("\\n", "\n").gsub(TAG, "").gsub(/\*\*|__/, "")
              .split("\n").map(&:strip).join("\n").strip
          end
        end
      end
    end
  end
end
