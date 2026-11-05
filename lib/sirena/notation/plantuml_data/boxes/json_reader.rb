# frozen_string_literal: true

require "json"
require_relative "../../../error/parse_error"

module Sirena
  module Notation
    module PlantUMLData
      module Boxes
        # Reads the JSON of a `@startjson` diagram.
        class JsonReader
          # @return [Hash, Array, String, Numeric, true, false, nil]
          # @raise [Sirena::Parser::ParseError] when the text is not JSON
          def call(text)
            JSON.parse(text, max_nesting: 100, allow_nan: false)
          rescue JSON::ParserError => e
            raise Sirena::Parser::ParseError,
                  "Parse error: JSON: #{e.message[0, 120]}"
          end
        end
      end
    end
  end
end
