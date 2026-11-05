# frozen_string_literal: true

require_relative "../unsupported_construct_error"

module Sirena
  module Notation
    module PlantUML
      module Activity
        # Turns PlantUML label markup into lines. Creole styling (`**bold**`,
        # `__underline__`, `<b>`, `<color:..>`) stays in the line for
        # {Creole} to draw and for {Creole.plain} to measure; an embedded
        # image or sprite is refused, never dropped.
        module Text
          module_function

          PLAIN = %r{</?plain>}i
          PICTURE = /<(?:img|\$|&)/i
          private_constant :PLAIN, :PICTURE

          # @param raw [String]
          # @param line [Integer] source line, for the refusal
          # @return [String] lines joined by newlines
          def clean(raw, line:)
            if PICTURE.match?(raw)
              raise UnsupportedConstructError.new(construct: "image",
                                                  line: line, text: raw)
            end

            raw.gsub("\\n", "\n").gsub(PLAIN, "")
              .split("\n").map(&:strip).join("\n").strip
          end
        end
      end
    end
  end
end
