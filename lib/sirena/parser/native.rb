# frozen_string_literal: true

module Sirena
  module Parser
    # The native parse path: Mermaid grammars compiled from PARG
    # (claricle/sirena-mermaid-parg) and run by the parsanol engine.
    #
    # It is strictly an accelerator. It answers only for input it accepts;
    # on a missing engine, an unreadable encoding or any rejection it
    # returns nil and the caller runs the Parslet grammar, which stays the
    # source of every positioned ParseError.
    module Native
      ARTIFACT_PATH = File.expand_path("native/mermaid.json", __dir__)
      DISABLE_VARIABLE = "SIRENA_NATIVE_PARSER"
      DISABLED_VALUES = %w[0 off false ruby].freeze
      private_constant :ARTIFACT_PATH, :DISABLE_VARIABLE, :DISABLED_VALUES

      class << self
        # @return [Boolean] whether the parsanol engine and artifact loaded
        def available?
          !artifact.nil?
        end

        # Parses source with one entry of the Mermaid artifact.
        #
        # @param entry [Symbol] an entry of mermaid.parg
        # @param source [String] Mermaid source
        # @return [Hash, Array, Parsanol::Slice, nil] the parse tree, or
        #   nil when the native path does not answer
        def parse(entry, source)
          return nil if disabled? || !readable?(source)

          artifact&.parse(entry.to_s, source)
        rescue Parsanol::ParseFailed
          nil
        end

        # Forgets the loaded artifact (specs swap the engine out).
        def reset!
          @artifact = nil
          @loaded = false
        end

        private

        def disabled?
          DISABLED_VALUES.include?(ENV.fetch(DISABLE_VARIABLE, "").downcase)
        end

        def readable?(source)
          source.encoding == Encoding::UTF_8 && source.valid_encoding?
        end

        def artifact
          return @artifact if @loaded

          @loaded = true
          @artifact = load_artifact
        end

        def load_artifact
          require "parsanol"
          Parsanol::PARG::Artifact.load(ARTIFACT_PATH)
        rescue LoadError, StandardError
          nil
        end
      end
    end
  end
end
