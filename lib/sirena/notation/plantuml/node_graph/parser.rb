# frozen_string_literal: true

require_relative "graph"
require_relative "reader"
require_relative "references"
require_relative "link"
require_relative "data_reader"
require_relative "archimate"
require_relative "entity_reader"
require_relative "../unsupported_construct_error"

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # Reads use case, component and deployment source into a {Graph}.
        class Parser
          include References
          include DataReader
          include EntityReader

          KEYWORDS = %w[package node database cloud rectangle folder frame
                        storage artifact card namespace component file
                        interface actor usecase portin portout circle
                        archimate].freeze
          CONTAINER = /\A(?<kw>#{KEYWORDS.join('|')})\s+(?<rest>.*?)\s*\{\z/i
          LEAF = /\A(?<kw>#{KEYWORDS.join('|')})\s+(?<rest>.+)\z/im
          SHORT = /\A(?<ref>\[[^\]]+\]|\([^()]+\)|:[^:\n]+:)
                   (?:\s+as\s+(?<alias>"[^"]+"|\(?[^\s()]+\)?))?
                   (?<tail>(?:\s*<<.*?>>)?(?:\s+\#\w+)?)\z/x
          BARE = /\A(?<id>#{IDENT})\s*(?<tail><<.*>>)\z/
          LOLLIPOP = /\A\(\)\s+(?<rest>.+)\z/
          SKIPPED = /\A(?:skinparam|hide|show|allow_?mixing|scale)\b/i
          SHAPES = /\A(?:queue|stack|agent|boundary|control|collections|
                    hexagon|label|person)\s/xi
          KEYWORDS_REFUSED = /\A(?:legend|header|footer|sprite|mainframe|
                              together)\b/xi
          REFUSED = { /\A<style>/i => "style block", /\A!/ => "preprocessor",
                      KEYWORDS_REFUSED => "keyword",
                      /\Afloating\s+note/i => "floating note",
                      SHAPES => "shape" }.freeze
          SIDE = /(?<side>left|right|top|bottom)(?:\s+of\s+(?<ref>#{REF}))?/
          NOTE = /\Anote\s+(?:#{SIDE}
                  |(?:"(?<quoted>.*)"\s+)?as\s+(?<name>\S+))
                  \s*(?::\s*(?<text>.*))?\z/xim

          # @param direction [Symbol] :left_to_right or :top_to_bottom
          # @param default_kind [Symbol] the kind of a bare name in a link
          def initialize(direction:, default_kind:)
            @graph = Graph.new(direction: direction)
            @default_kind = default_kind
            @stack = []
            @counter = 0
          end

          # @return [Graph]
          # @raise [UnsupportedConstructError]
          def parse(source)
            @entries = Reader.entries(source)
            @index = 0
            while @index < @entries.size
              text, number = @entries[@index]
              @index += 1
              statement(text, number)
            end
            @graph
          end

          private

          def statement(text, number)
            @number = number
            @text = text
            return if skip?(text)

            handlers = %i[close container note short lollipop data entity leaf
                          bare er_edge edge]
            handlers.any? { |name| send(:"take_#{name}", text) } ||
              refuse("statement")
          end

          def skip?(text)
            refuse_known(text)
            title(text) || direction(text) || skip_setting(text)
          end

          def refuse_known(text)
            REFUSED.each do |pattern, name|
              refuse(name) if text.match?(pattern)
            end
          end

          def skip_setting(text)
            return unless text.match?(SKIPPED)

            @mixing ||= text.match?(DataReader::MIXING)
            skip_block if text.end_with?("{")
            :skipped
          end

          def skip_block
            @index += 1 until @index >= @entries.size ||
                @entries[@index].first == "}"
            @index += 1
          end

          def title(text)
            return unless (m = text.match(/\Atitle\s+(.+)\z/i))

            @graph.title = m[1]
          end

          def direction(text)
            case text
            when /\Aleft to right direction\z/i
              @graph.direction = :left_to_right
            when /\Atop to bottom direction\z/i
              @graph.direction = :top_to_bottom
            end
          end

          def refuse(construct)
            raise UnsupportedConstructError.new(construct: construct,
                                                line: @number, text: @text)
          end

          def take_close(text)
            @stack.pop if text == "}"
          end

          def take_container(text)
            return unless (m = text.match(CONTAINER))

            kw = m[:kw].downcase.to_sym
            node = declare(kw, m[:rest])
            node.container = true
            @stack.push(node)
          end

          def take_leaf(text)
            return unless (m = text.match(LEAF))

            declare(m[:kw].downcase.to_sym, m[:rest])
          end

          def take_lollipop(text)
            return unless (m = text.match(LOLLIPOP))

            declare(:interface, m[:rest])
          end

          def take_short(text)
            return unless (m = text.match(SHORT))

            kind, name = bracketed(m[:ref])
            id = m[:alias]&.delete_prefix('"')&.delete_suffix('"')
            node = place(name, kind, id ? unbracket(id) : name)
            style(node, m[:tail])
          end

          def take_bare(text)
            return unless (m = text.match(BARE))

            style(place(m[:id], @default_kind, m[:id]), m[:tail])
          end

          def take_note(text)
            return unless (m = text.match(NOTE))

            body = m[:text] || m[:quoted] || note_body
            id = m[:name] || "note#{@counter += 1}"
            note = @graph.node(id, :note, parent: @stack.last)
            note.lines = References.lines_of(body)
            link_note(note, m[:ref], m[:side])
            note
          end

          def note_body
            lines = []
            while @index < @entries.size
              text, = @entries[@index]
              @index += 1
              break if text.match?(/\Aend\s*note\z/i)

              lines << text
            end
            lines.join("\n")
          end

          # A note beside (`left`, `right`) its target sits in the target's
          # rank, one above or below (`top`, `bottom`) in the next.
          def link_note(note, ref, side)
            return unless ref

            beside = %w[left right].include?(side)
            @graph.edges << Edge.new(from: note, to: resolve(ref),
                                     style: :dashed, width: 1,
                                     rank_step: beside ? 0 : 1,
                                     backwards: %w[right bottom].include?(side))
          end

          def take_edge(text)
            return unless (m = text.match(EDGE))

            link = Link.new(m[:arrow])
            link.hidden? ? @graph : add_edge(m, link)
          end

          def add_edge(match, link)
            from = resolve(match[:a])
            to = resolve(match[:b])
            rows = { from_row: row_index(from, port(match, :aport)),
                     to_row: row_index(to, port(match, :bport)) }
            @graph.edges << link.edge(from, to, label: match[:label]&.strip,
                                                **rows)
          end

          # @return [String, nil] a link end's row name; an entity link has
          #   no ports and so no such capture
          def port(match, name)
            match[name] if match.names.include?(name.to_s)
          end

          # Declares `rest` -- a name, a label and an optional alias -- as a
          # node of `kind`.
          def declare(kind, rest)
            stereo = rest[STEREOTYPE, :st]
            color = rest[COLOR, :color] || rest[LEADING_COLOR, :color]
            id, label = names(bare_name(rest))
            kind = :usecase if kind == :usecase
            node = place(label, kind, id)
            node.stereotype = kind == :archimate ? nil : stereo
            node.color = kind == :archimate ? Archimate.color(color) : color
            node
          end

          def bare_name(rest)
            rest.sub(STEREOTYPE, "").sub(COLOR, "").sub(LEADING_COLOR, "")
              .strip
          end

          def names(rest)
            case rest
            when /\A"(.*)"\s+as\s+(\S+)\z/m then [unbracket($2), $1]
            when /\A(\S+)\s+as\s+"(.*)"\z/m then [unbracket($1), $2]
            when /\A(\S+)\s+\[(.*)\]\z/m then [$1, $2]
            when /\A(\S+)\s+as\s+(\S+)\z/ then [unbracket($2), unbracket($1)]
            else
              name = unbracket(rest.delete_prefix('"').delete_suffix('"'))
              [name, name]
            end
          end

          def unbracket(name)
            name.sub(/\A[(\[:]/, "").sub(/[)\]:]\z/, "")
          end

          def style(node, tail)
            return node if tail.to_s.strip.empty?

            node.stereotype = tail[STEREOTYPE, :st] || node.stereotype
            node.color = tail[/#(\w+)\s*\z/, 1] || node.color
            node
          end

          # Creates or updates the node `id`.
          def place(label, kind, id)
            existing = @graph.nodes[id]
            node = existing || @graph.node(id, kind, parent: @stack.last)
            node.kind = kind if existing
            node.lines = References.lines_of(label)
            node
          end

          def bracketed(ref)
            kind = { "[" => :component, "(" => :usecase,
                     ":" => :actor }.fetch(ref[0])
            [kind, ref[1..-2]]
          end

          # @return [Node] the node a link end names, made if it is new
          def resolve(ref)
            kind, name = if ref.match?(BRACKET)
                           bracketed(ref)
                         else
                           [@default_kind,
                            ref.delete_prefix('"').delete_suffix('"')]
                         end
            @graph.find(name) || @graph.node(name, kind, parent: @stack.last)
          end
        end
      end
    end
  end
end
