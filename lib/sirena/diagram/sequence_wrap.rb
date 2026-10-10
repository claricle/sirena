# frozen_string_literal: true

module Sirena
  module Diagram
    # Mermaid's global sequence wrap switch: the bare `%%{wrap}%%`
    # directive, or an `init` directive with `wrap: true` at the top level
    # or under `sequence`. The directive may sit before or after the
    # `sequenceDiagram` line.
    module SequenceWrap
      DIRECTIVE = /%%\{(.*?)\}%%/m
      BARE = /\A\s*wrap\s*\z/
      INIT_WRAP = /\A\s*init(?:ialize)?\s*:.*["']?\bwrap["']?\s*:\s*true\b/mi

      # @param source [String] the whole Mermaid source
      # @return [Boolean] whether every sequence text wraps by default
      def self.on?(source)
        source.scan(DIRECTIVE).flatten.any? do |body|
          body.match?(BARE) || body.match?(INIT_WRAP)
        end
      end
    end
  end
end
