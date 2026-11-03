# frozen_string_literal: true

require_relative "../../sirena"
require_relative "plantuml_salt/layout"
require_relative "plantuml_salt/parser"
require_relative "plantuml_salt/renderer"

module Sirena
  module Notation
    # The PlantUML salt notation: `@startsalt ... @endsalt` UI mock-ups,
    # drawn as a static picture. Constructs it does not know are shown as
    # plain text.
    module PlantUMLSalt
      extend self

      # `@startsalt` after an optional byte order mark and any run of blank
      # lines and `'` comment lines. Matched on raw bytes so no input, valid
      # UTF-8 or not, can make it raise.
      PAD = '[ \t\v\f\x00]'
      OPENER = /\A(?:\xEF\xBB\xBF)?
                (?:#{PAD}*(?:'[^\r\n]*)?(?:\r\n|\r|\n))*
                #{PAD}*@startsalt(?![A-Za-z0-9_])/xn
      NOT_FOUND = "Unable to detect diagram type from source. " \
                  "Source must start with one of: @startsalt"
      private_constant :PAD, :OPENER, :NOT_FOUND

      # @return [Symbol] the notation identifier
      def id
        :plantuml_salt
      end

      # @return [Array<String>] file extensions this notation reads
      def extensions
        %w[.salt].freeze
      end

      # @return [Array<Symbol>] diagram types
      def types
        %i[salt].freeze
      end

      # @param source [String] any String, including binary or invalid UTF-8
      # @return [Boolean] whether the source opens a salt diagram
      def claims?(source)
        source.is_a?(String) && source.b.match?(OPENER)
      end

      # @param source [String] salt source
      # @return [Notation::Parsed]
      # @raise [Engine::DiagramTypeError] when the source has no
      #   `@startsalt`
      def parse(source)
        raise Engine::DiagramTypeError, NOT_FOUND unless claims?(source)

        Notation::Parsed.new(
          type: :salt,
          diagram: Parser.new.parse(source),
          transform: Layout,
          renderer: Renderer,
        )
      end
    end
  end
end

Sirena::Notation.register(Sirena::Notation::PlantUMLSalt)
