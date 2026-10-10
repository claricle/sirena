# frozen_string_literal: true

require_relative "../../sirena"
require_relative "plantuml/parser"
require_relative "plantuml/ir_adapter"
require_relative "plantuml/layout"
require_relative "plantuml/renderer"
require_relative "plantuml/sequence"

module Sirena
  module Notation
    # The PlantUML notation: class diagrams, and sequence diagrams in
    # {Sequence}.
    #
    # Not loaded by `require "sirena"`: a consumer requires this file, which
    # is how an external notation is meant to arrive (10a, "Discovery").
    # Registration with the notation registry waits for the registry itself.
    #
    # The identity methods below follow the plugin interface in
    # TODO.foundation/10a-notation-contract.md, section 4.
    module PlantUML
      extend self

      # What `String#strip` removes from a line, which is what the parser
      # strips before it reads one. The opener must skip exactly that set, or
      # `claims?` and `parse` disagree about what is PlantUML.
      PAD = '[ \t\v\f\x00]'

      # `@startuml` after an optional byte order mark and any run of blank lines
      # and `'` comment lines. Matched on raw bytes so no input, valid UTF-8 or
      # not, can make it raise.
      OPENER = /\A(?:\xEF\xBB\xBF)?
                (?:#{PAD}*(?:'[^\r\n]*)?(?:\r\n|\r|\n))*
                #{PAD}*@startuml(?![A-Za-z0-9_])/xn
      private_constant :PAD, :OPENER

      # @return [Symbol] the notation identifier
      def id
        :plantuml
      end

      # @return [Array<String>] file extensions this notation reads
      def extensions
        %w[.puml].freeze
      end

      # @return [Array<Symbol>] diagram types, in display order
      def types
        %i[class_diagram sequence_diagram].freeze
      end

      # @param source [String] any String, including binary or invalid UTF-8
      # @return [Boolean] whether the source opens a PlantUML diagram
      def claims?(source)
        source.is_a?(String) && source.b.match?(OPENER)
      end

      # Parses one class or sequence diagram and names the PlantUML-local back
      # half of the rendering pipeline. Nothing in Engine knows this notation
      # exists.
      #
      # @param source [String] PlantUML source
      # @return [Notation::Parsed]
      def parse(source)
        return Sequence.parse(source) if Sequence.sequence?(source)

        Notation::Parsed.new(
          type: :class_diagram,
          diagram: IRAdapter.call(Parser.new.parse(source)),
          transform: Layout,
          renderer: Renderer,
        )
      end
    end
  end
end

Sirena::Notation.register(Sirena::Notation::PlantUML)
