# frozen_string_literal: true

require_relative "error"
require_relative "error/pipeline_error"

module Sirena
  # Picks the engine behind {Sirena.render}: the Rust runtime shipped by the
  # optional `sirena-native` gem, or this gem's own Ruby pipeline.
  #
  # `SIRENA_RUNTIME` selects the mode:
  #
  # - `auto` (default) -- Rust when `sirena-native` loads and finds its
  #   shared library, Ruby otherwise. Whenever Rust cannot answer (the diagram
  #   type is not ported, or it reports an error) the Ruby pipeline renders
  #   the same source, so a failure is always the Ruby exception, never a
  #   native one.
  # - `ruby` -- never touch the native runtime.
  # - `rust` -- require it: a missing library, an unported diagram type or a
  #   native error raises {Engine::PipelineError}. For CI jobs proving
  #   the Rust path.
  #
  # The Rust runtime takes only a source string, so it is used just for a
  # default render (no options) of a source the Mermaid notation handles.
  # Anything else is the Ruby pipeline's job, and the SVG bytes are the same
  # either way.
  module Runtime
    ENV_KEY = "SIRENA_RUNTIME"
    MODES = %w[auto ruby rust].freeze
    private_constant :ENV_KEY, :MODES

    class << self
      # @return [String] the validated mode
      # @raise [ArgumentError] when SIRENA_RUNTIME names no mode
      def mode
        value = ENV.fetch(ENV_KEY, nil)
        return "auto" if value.nil? || value.empty?
        return value if MODES.include?(value)

        raise ArgumentError,
              "#{ENV_KEY} must be one of #{MODES.join(', ')}, " \
              "got #{value.inspect}"
      end

      # Whether the native library is loadable in this process.
      def native?
        !library.nil?
      end

      # SVG from the Rust runtime, or nil when the caller should render in Ruby.
      #
      # @param source [String]
      # @param options [Hash] Engine#render options; any key rules Rust out
      # @return [String, nil]
      def render(source, options)
        selected = mode
        return nil if selected == "ruby"

        strict = selected == "rust"
        if native_eligible?(source, options)
          return native_render(source, strict: strict)
        end

        decline("options or a non-Mermaid notation", strict: strict)
      end

      # Forget the memoised library probe (specs only).
      def reset!
        return unless instance_variable_defined?(:@library)

        remove_instance_variable(:@library)
      end

      private

      def native_render(source, strict:)
        lib = library
        return lib.render(source) unless lib.nil?

        decline("sirena-native is not installed", strict: strict)
      rescue ::Sirena::Native::Unported => e
        decline("#{e.message} is not ported", strict: strict)
      rescue ::Sirena::Native::RenderError => e
        decline("it failed: #{e.message}", strict: strict)
      rescue EncodingError
        nil
      end

      # Nil sends the caller to Ruby; strict mode refuses instead.
      def decline(reason, strict:)
        return nil unless strict

        raise Engine::PipelineError,
              "SIRENA_RUNTIME=rust cannot render: #{reason}"
      end

      def native_eligible?(source, options)
        return false unless options.empty? && source.is_a?(String)

        notation = Notation.resolve(explicit: nil, path: nil, source: source)
        notation.id == :mermaid
      end

      # The Native::Library, or nil. Probed once: `require` of an absent gem
      # means "use Ruby".
      def library
        return @library if instance_variable_defined?(:@library)

        @library = probe
      end

      def probe
        require "sirena/native"
        ::Sirena::Native.library
      rescue LoadError
        nil
      end
    end
  end
end
