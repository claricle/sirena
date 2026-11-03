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
      ARTIFACT_VARIABLE = "SIRENA_NATIVE_ARTIFACT"
      DISABLE_VARIABLE = "SIRENA_NATIVE_PARSER"
      DISABLED_VALUES = %w[0 off false ruby].freeze
      # The engine recurses on the machine stack once per nested block and
      # a source that nests deeper than the stack allows kills the whole
      # process (a segfault in the extension, not a SystemStackError): about
      # 60 nested subgraphs on a 1 MB stack, Windows' main-thread size. Past
      # this depth the Ruby grammar answers, as it does without the engine.
      MAX_NESTING = 32
      NESTING_OPEN = /\A\s*(?:subgraph|block:|alt|loop|opt|par|critical|break|
                            rect|box)\b|\{\s*\z/ix
      NESTING_CLOSE = /\A\s*(?:end\b|\})/i
      private_constant :ARTIFACT_PATH, :ARTIFACT_VARIABLE, :DISABLE_VARIABLE,
                       :DISABLED_VALUES, :MAX_NESTING, :NESTING_OPEN,
                       :NESTING_CLOSE

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
          return nil if disabled? || !readable?(source) || too_deep?(source)

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

        # Whether blocks opened and not yet closed ever pass MAX_NESTING.
        # A line that merely looks like an opener only sends the source to
        # the Ruby grammar, which answers identically.
        def too_deep?(source)
          depth = 0
          source.each_line do |line|
            if line.match?(NESTING_OPEN)
              depth += 1
              return true if depth > MAX_NESTING
            elsif line.match?(NESTING_CLOSE)
              depth -= 1 if depth.positive?
            end
          end
          false
        end

        def artifact
          return @artifact if @loaded

          @loaded = true
          @artifact = load_artifact
        end

        def load_artifact
          require "parsanol"
          Parsanol::PARG::Artifact.load(ENV.fetch(ARTIFACT_VARIABLE,
                                                  ARTIFACT_PATH))
        rescue LoadError, StandardError
          nil
        end
      end
    end
  end
end
