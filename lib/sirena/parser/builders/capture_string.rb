# frozen_string_literal: true

module Sirena
  module Parser
    module Builders
      # Parslet captures an empty `.repeat.as(:string)` as `[]`, not as an
      # empty slice, so `""` would otherwise render as the text "[]".
      module CaptureString
        private

        def capture_string(capture)
          capture.is_a?(Array) ? "" : capture.to_s
        end
      end
    end
  end
end
