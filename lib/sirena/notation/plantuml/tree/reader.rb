# frozen_string_literal: true

require_relative "../../../ir"
require_relative "../source_lines"
require_relative "../unsupported_construct_error"
require_relative "role"

module Sirena
  module Notation
    module PlantUML
      module Tree
        # Reads a PlantUML mindmap or work breakdown structure into the
        # hierarchy graph Sirena's mindmap already uses.
        #
        # A line is a run of `*` (or `+` and `-`, which also pick the side of
        # the root) followed by the text; the run's length is the depth. A
        # `:` in place of the space opens a multi-line text closed by a line
        # ending in `;`. A `_` after the run draws no box, a `[#colour]`
        # fills the box, and `<<name>>` at the end of the text applies the
        # `.name` colour of a `<style>` block. Every other style property is
        # read and dropped. A line outside this subset raises
        # {UnsupportedConstructError}.
        class Reader
          ITEM = /\A([*+-]+)([<>])?(_)?(?:\[(\#?\w+)\])?(:|[ \t])[ \t]*(.*)\z/
          SKIPPED = /\A(?:title|header|footer|caption|legend|skinparam|scale|
                     !theme|hide|show|left[ ]to[ ]right[ ]direction|
                     top[ ]to[ ]bottom[ ]direction)\b/xi
          STYLE_OPEN = /\A<style>/i
          STYLE_CLOSE = %r{</style>\z}i
          CLASS_STYLE = /\.(\w+)[ \t]*\{([^{}]*)\}/m
          BACKGROUND = /BackgroundColor[ \t]+(\#?\w+)/i
          TRAILING_CLASS = /[ \t]*<<(\w+)>>\z/
          CODE_TAG = %r{\A</?code>\z}i
          private_constant :ITEM, :SKIPPED, :STYLE_OPEN, :STYLE_CLOSE,
                           :CLASS_STYLE, :BACKGROUND, :TRAILING_CLASS,
                           :CODE_TAG

          # One line of the source, as read.
          Entry = Struct.new(:id, :depth, :side, :boxless, :fill, :lines,
                             :parent, keyword_init: true)
          private_constant :Entry

          # @param source [String] PlantUML source
          # @param id [String] the graph's id, which names the kind
          # @return [Sirena::IR::Graph]
          # @raise [UnsupportedConstructError] on a line outside the subset
          def parse(source, id:)
            @entries = []
            @classes = {}
            @open = nil
            @style = nil
            SourceLines.of(source).each { |text, number| read(text, number) }
            IR::Graph.new(id: id, role: "hierarchy", nodes: nodes,
                          edges: edges)
          end

          private

          def read(text, number)
            return continue_text(text) if @open
            return style_line(text) if @style
            return if SKIPPED.match?(text)
            return style_line(text.sub(STYLE_OPEN, ""), opening: true) if
              STYLE_OPEN.match?(text)

            item = ITEM.match(text)
            raise refused(text, number) unless item

            start_item(item)
          end

          def refused(text, number)
            UnsupportedConstructError.new(
              construct: "mindmap statement", line: number, text: text,
            )
          end

          def style_line(text, opening: false)
            @style = [] if opening
            @style << text.sub(STYLE_CLOSE, "")
            close_style if STYLE_CLOSE.match?(text)
          end

          def close_style
            sheet = @style.join("\n").gsub(%r{//[^\n]*}, "")
            sheet.scan(CLASS_STYLE) do |name, properties|
              colour = BACKGROUND.match(properties)
              @classes[name] = colour[1] if colour
            end
            @style = nil
          end

          def start_item(match)
            marks, hang, boxless, colour, joint, rest = match.captures
            entry = Entry.new(depth: marks.length, boxless: !boxless.nil?,
                              fill: colour, lines: [])
            attach(entry, marks[0], hang)
            settle(entry, joint, rest)
          end

          def settle(entry, joint, rest)
            return @open = entry.tap { entry.lines << rest } if
              joint == ":" && !rest.end_with?(";")

            finish(entry, joint == ":" ? rest.delete_suffix(";") : rest)
          end

          def continue_text(text)
            return if CODE_TAG.match?(text)
            return @open.lines << text unless text.end_with?(";")

            entry = @open
            @open = nil
            last = text == ";" ? "" : text.delete_suffix(";")
            finish(entry, last, continued: true)
          end

          def finish(entry, last, continued: false)
            entry.lines.pop if continued && entry.lines.last.to_s.empty?
            entry.lines << last
            entry.lines[-1] = classed(entry, entry.lines.last)
            entry
          end

          def classed(entry, text)
            match = TRAILING_CLASS.match(text)
            return text unless match

            entry.fill ||= @classes[match[1]]
            text.sub(TRAILING_CLASS, "")
          end

          # The parent is the nearest earlier entry one level up; a first
          # level entry is a root of its own.
          def attach(entry, mark, hang)
            entry.id = "n#{@entries.length + 1}"
            entry.parent = @entries.reverse.find do |other|
              other.depth < entry.depth
            end
            entry.side = side_of(entry.parent, mark, hang)
            @entries << entry
          end

          def side_of(parent, mark, hang)
            return "left" if mark == "-" || hang == "<"
            return "right" if mark == "+" || hang == ">"

            parent ? parent.side : "right"
          end

          def nodes
            @entries.map do |entry|
              role = Role.spell(side: entry.side, boxless: entry.boxless,
                                fill: entry.fill)
              IR::Node.new(id: entry.id, label: entry.lines.join("\n"),
                           parent_id: entry.parent&.id, role: role)
            end
          end

          def edges
            @entries.select(&:parent).map do |entry|
              IR::Edge.new(id: "#{entry.parent.id}_to_#{entry.id}",
                           source_id: entry.parent.id, target_id: entry.id,
                           role: "parent_child")
            end
          end
        end
      end
    end
  end
end
