# frozen_string_literal: true

require_relative "../../sirena"
require_relative "plantuml_data/boxes/highlights"
require_relative "plantuml_data/boxes/json_reader"
require_relative "plantuml_data/boxes/renderer"
require_relative "plantuml_data/boxes/table"
require_relative "plantuml_data/boxes/tree_builder"
require_relative "plantuml_data/boxes/tree_layout"
require_relative "plantuml_data/boxes/yaml_reader"

module Sirena
  module Notation
    # The PlantUML data notation: `@startjson ... @endjson` and
    # `@startyaml ... @endyaml`, drawn as a tree of key and value boxes.
    module PlantUMLData
      extend self

      PAD = '[ \t\v\f\x00]'
      OPENER = /\A(?:\xEF\xBB\xBF)?
                (?:#{PAD}*(?:'[^\r\n]*)?(?:\r\n|\r|\n))*
                #{PAD}*@start(json|yaml)(?![A-Za-z0-9_])/xn
      NOT_FOUND = "Unable to detect diagram type from source. " \
                  "Source must start with one of: @startjson, @startyaml"
      READERS = { "json" => PlantUMLData::Boxes::JsonReader,
                  "yaml" => PlantUMLData::Boxes::YamlReader }.freeze
      private_constant :PAD, :OPENER, :NOT_FOUND, :READERS

      # @return [Symbol] the notation identifier
      def id
        :plantuml_data
      end

      # @return [Array<String>] file extensions this notation reads
      def extensions
        [].freeze
      end

      # @return [Array<Symbol>] diagram types
      def types
        %i[json_diagram yaml_diagram].freeze
      end

      # @param source [String] any String, including binary or invalid UTF-8
      # @return [Boolean] whether the source opens a JSON or YAML diagram
      def claims?(source)
        source.is_a?(String) && source.b.match?(OPENER)
      end

      # @param source [String] `@startjson` or `@startyaml` source
      # @return [Notation::Parsed]
      # @raise [Engine::DiagramTypeError] when the source has no opener
      # @raise [Sirena::Parser::ParseError] when the data does not parse
      def parse(source)
        raise Engine::DiagramTypeError, NOT_FOUND unless claims?(source)

        kind = source.b.match(OPENER)[1]
        Notation::Parsed.new(
          type: :"#{kind}_diagram",
          diagram: diagram(kind, body(source, kind)),
          transform: PlantUMLData::Boxes::TreeLayout,
          renderer: PlantUMLData::Boxes::Renderer,
        )
      end

      private

      def body(source, kind)
        text = source.dup.force_encoding(Encoding::UTF_8).scrub
        text = text.delete_prefix("﻿").sub(/\A.*?@start#{kind}[^\n]*\n/m, "")
        text.sub(/^[ \t]*@end#{kind}.*\z/m, "")
      end

      def diagram(kind, body)
        highlights, data = PlantUMLData::Boxes::Highlights.extract(body)
        value = READERS.fetch(kind).new.call(data)
        table = PlantUMLData::Boxes::TreeBuilder.new(highlights).call(value)
        PlantUMLData::Boxes::Diagram.new(tables: [table])
      end
    end
  end
end

Sirena::Notation.register(Sirena::Notation::PlantUMLData)
