# frozen_string_literal: true

require_relative "../arrow"
require_relative "map_rows"
require_relative "../../plantuml_data/boxes/table"
require_relative "../../plantuml_data/boxes/json_reader"
require_relative "../../plantuml_data/boxes/highlights"
require_relative "../../plantuml_data/boxes/tree_builder"
require_relative "../../plantuml_data/boxes/text"
require_relative "../../../error/parse_error"
require_relative "../unsupported_construct_error"

module Sirena
  module Notation
    module PlantUML
      module Objects
        # Reads PlantUML's object diagram: `object`, `map` and `json`
        # elements, empty `class` boxes, and the relations between them. A
        # line outside that subset raises {UnsupportedConstructError}.
        class Reader
          NAME = MapRows::NAME
          LABELLED = /(?:"([^"]+)"[ \t]+as[ \t]+(#{NAME})|(#{NAME}))/o
          ELEMENT = /\A(object|class|abstract class|interface)[ \t]+
                     #{LABELLED}(?:[ \t]*(\{))?\z/xo
          MAP = /\Amap[ \t]+#{LABELLED}[ \t]*\{\z/o
          JSON_OPEN = /\Ajson[ \t]+#{LABELLED}[ \t]*\{(.*)\z/o
          END_TEXT = '(?:"([^"]+)"[ \t]+)?'
          END_REF = "(#{NAME}(?:::#{NAME})?)".freeze
          RELATION = /\A#{END_REF}[ \t]+#{END_TEXT}#{Arrow::PATTERN}[ \t]*
                      #{END_TEXT}#{END_REF}(?:[ \t]*:[ \t]*(.+))?\z/xo
          START = /\A@startuml(?:[ \t]+\S.*)?\z/
          TITLE = /\Atitle[ \t]+(.+)\z/i
          DIRECTION = /\A(left to right|top to bottom) direction\z/i
          SKIPPED = /\A(?:skinparam|hide|show|scale)\b/i
          Boxes = PlantUMLData::Boxes
          TREE_GLYPH = { dashed: true, markers: {}.freeze }.freeze
          private_constant :Boxes, :TREE_GLYPH, :NAME, :LABELLED, :ELEMENT,
                           :MAP, :JSON_OPEN,
                           :END_TEXT, :END_REF,
                           :RELATION, :START, :TITLE, :DIRECTION, :SKIPPED

          # @return [Array<Array(String, Integer)>] the stripped, non-empty,
          #   non-comment lines of the first diagram with their numbers
          def self.lines_of(source)
            numbered(source)
              .drop_while { |line, _| !line.start_with?("@start") }
              .take_while { |line, _| !line.start_with?("@end") }
              .reject { |line, _| line.empty? || line.start_with?("'") }
          end

          def self.numbered(source)
            text = source.dup.force_encoding(Encoding::UTF_8).scrub
            text.lines.map.with_index { |line, i| [line.strip, i + 1] }
          end
          private_class_method :numbered

          # @param source [String] PlantUML source
          # @return [Boxes::Diagram]
          def parse(source)
            @tables = {}
            @links = []
            @title = nil
            @direction = :down
            lines = self.class.lines_of(source)
            @queue = lines.drop(1)
            read(@queue.shift) until @queue.empty?
            implicit_tables
            Boxes::Diagram.new(tables: @tables.values, links: @links,
                               title: @title, direction: @direction)
          end

          private

          # An end of a relation nobody declared is an object of that name.
          def implicit_tables
            @links.flat_map { |l| [l.from, l.to] }.each do |id|
              @tables[id] ||= Boxes::Table.new(id: id, title: id, rows: [],
                                               kind: :object,
                                               group: packages(id))
            end
          end

          def read(entry)
            @text, @number = entry
            return if skipped?

            [method(:element), method(:map), method(:json), method(:relation)]
              .any?(&:call) || refuse
          end

          def skipped?
            @text.match?(SKIPPED) || @text.match?(START) || title? || direction?
          end

          def title?
            match = TITLE.match(@text)
            match && (@title = Boxes::Text.plain(match[1]))
          end

          def direction?
            match = DIRECTION.match(@text)
            match && (@direction = horizontal?(match[1]) ? :right : :down)
          end

          def horizontal?(phrase)
            phrase.downcase.start_with?("left")
          end

          def refuse
            raise UnsupportedConstructError.new(
              construct: @text[/\A\S+/].to_s.downcase, line: @number,
              text: @text
            )
          end

          def declare(label, as_name, name, kind, rows = [])
            id = as_name || name
            @tables[id] = Boxes::Table.new(id: id, title: label || name,
                                           rows: rows, kind: kind,
                                           group: as_name ? [] : packages(id))
          end

          # @return [Array<String>] the packages a dotted name stands in
          def packages(name)
            name.split(".")[0...-1]
          end

          def element
            match = ELEMENT.match(@text) or return false
            kind, label, as_name, name, open = match.captures
            rows = open ? body_lines.map { |l| Boxes::Row.new(value: l) } : []
            declare(label, as_name, name, kind == "object" ? :object : :class,
                    rows)
          end

          def body_lines
            lines = []
            while (entry = @queue.shift)
              return lines if entry.first == "}"

              lines << entry.first
            end
            raise Sirena::Parser::ParseError,
                  "Parse error: unclosed { at line #{@number}"
          end

          def map
            match = MAP.match(@text) or return false
            label, as_name, name = match.captures
            rows, links = MapRows.call(body_lines)
            declare(label, as_name, name, :map, rows)
            map_links(as_name || name, links)
          end

          # A map row's `*->` is a plain line out of the row: the JAR draws no
          # composition diamond for it.
          def map_links(id, links)
            links.each do |key, glyph, target|
              @links << link(id, target, Arrow.parse(glyph.delete("*")), [],
                             key)
            end
          end

          def json
            match = JSON_OPEN.match(@text) or return false
            label, as_name, name, rest = match.captures
            value = Boxes::JsonReader.new.call("{#{json_body(rest)}")
            root = Boxes::TreeBuilder.new(Boxes::Highlights.new).call(value)
            adopt(root, label, as_name || name)
          end

          def json_body(first)
            text = first.dup
            while unbalanced?(text) && (entry = @queue.shift)
              text << "\n" << entry.first
            end
            text
          end

          def unbalanced?(text)
            text.count("{") + 1 > text.count("}")
          end

          def adopt(root, label, id)
            table = Boxes::Table.new(id: id, title: label || id,
                                     rows: root.rows, kind: :tree)
            @tables[id] = table
            walk(table, "#{id}.")
          end

          def walk(table, prefix)
            table.rows.each_with_index do |row, i|
              next unless row.child

              child = Boxes::Table.new(id: "#{prefix}#{i}",
                                       rows: row.child.rows, kind: :tree)
              @tables[child.id] = child
              @links << Boxes::Link.new(from: table.id, to: child.id,
                                        from_row: row, glyph: TREE_GLYPH)
              walk(child, "#{child.id}.")
            end
          end

          def relation
            match = RELATION.match(@text) or return false
            from, left_text, glyph, right_text, to, label = match.captures
            parsed = Arrow.parse(glyph) or return false
            @links << link(from, to, parsed, [left_text, right_text, label])
          end

          def link(from, to, glyph, texts, from_port = nil)
            source, port = from.split("::")
            target, target_port = to.split("::")
            Boxes::Link.new(from: source, to: target, glyph: glyph,
                            from_row: from_port || port, to_row: target_port,
                            label: texts.compact.join(" "))
          end
        end
      end
    end
  end
end
