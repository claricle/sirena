# frozen_string_literal: true

require_relative "../../error"
require_relative "../../error/diagram_type_error"
require_relative "../../error/parse_error"
require_relative "diagram_builder"
require_relative "member"
require_relative "relation"
require_relative "unsupported_construct_error"
require_relative "unsupported_constructs"

module Sirena
  module Notation
    module PlantUML
      # Reads the PlantUML class-diagram subset, enumerated in
      # spec/plantuml_spike/subset.yml. A line outside it raises
      # {UnsupportedConstructError}; never return a diagram with a line
      # skipped.
      #
      # Inside this namespace `Parser` is this class, so a neighbour is always
      # written `Sirena::Parser::...`.
      #
      # @example
      #   Parser.new.parse("@startuml\nclass A\nA --> B\n@enduml\n")
      class Parser
        NAME = /[A-Za-z_][A-Za-z0-9_]*/
        VISIBILITY = { "+" => :public, "-" => :private, "#" => :protected,
                       "~" => :package }.freeze
        KINDS = { "class" => :class, "abstract class" => :abstract,
                  "interface" => :interface }.freeze

        # glyph => the Relation kind and the side its marker sits on
        ARROWS = {
          "<|--" => { kind: :extension, head: :left },
          "--|>" => { kind: :extension, head: :right },
          "<|.." => { kind: :implementation, head: :left },
          "..|>" => { kind: :implementation, head: :right },
          "-->" => { kind: :association, head: :right },
          "<--" => { kind: :association, head: :left },
          "--" => { kind: :association, head: nil },
          "o--" => { kind: :aggregation, head: :left },
          "--o" => { kind: :aggregation, head: :right },
          "*--" => { kind: :composition, head: :left },
          "--*" => { kind: :composition, head: :right },
        }.freeze

        # Every quantified piece is separated from the next by a character
        # it cannot also match, so no line backtracks more than linearly.
        STARTUML = /\A@startuml(?![A-Za-z0-9_])/
        CLASS_DECLARATION =
          /\A(abstract[ \t]+class|class|interface)[ \t]+(#{NAME})
           (?:[ \t]*(\{))?\z/xo
        RELATION = /\A(#{NAME})[ \t]+(?:"([^"]+)"[ \t]+)?
                    (#{Regexp.union(ARROWS.keys.sort_by { |g| -g.length })})
                    [ \t]+(?:"([^"]+)"[ \t]+)?(#{NAME})
                    (?:[ \t]*:[ \t]*(.+))?\z/xo
        METHOD = /\A([+\-#~])?[ \t]*(#{NAME})[ \t]*\(([^()]*)\)
                  (?:[ \t]*:[ \t]*(.+))?\z/xo
        FIELD = /\A([+\-#~])?[ \t]*(#{NAME})(?:[ \t]*:[ \t]*([^()]+))?\z/o
        LINE_END = /\r\n|\r|\n/
        NOT_FOUND_MESSAGE = "Unable to detect diagram type from source. " \
                            "Source must start with one of: @startuml"

        private_constant :NAME, :VISIBILITY, :KINDS, :ARROWS, :STARTUML,
                         :CLASS_DECLARATION, :RELATION, :METHOD, :FIELD,
                         :LINE_END, :NOT_FOUND_MESSAGE

        # @param source [String] PlantUML source
        # @return [Diagram] the parsed diagram; the Diagram, its collections
        #   and its records are frozen
        # @raise [Engine::DiagramTypeError] when the source does not start
        #   with @startuml
        # @raise [UnsupportedConstructError] on the first line outside the
        #   subset
        # @raise [Sirena::Parser::ParseError] when the source is not valid
        #   UTF-8, @enduml is missing or a class body is never closed
        def parse(source)
          builder = DiagramBuilder.new
          phase = :before
          lines_of(source).each_with_index do |line, index|
            phase = step(phase, builder, line.strip, index + 1)
          end
          finish(phase, builder)
        end

        private

        # Invalid bytes are refused, not scrubbed: a scrubbed name would
        # silently rename a class.
        def lines_of(source)
          text = source.dup.force_encoding(Encoding::UTF_8)
          unless text.valid_encoding?
            raise Sirena::Parser::ParseError,
                  "Parse error: source is not valid UTF-8"
          end

          text.delete_prefix("\uFEFF").split(LINE_END)
        end

        def step(phase, builder, text, number)
          return phase if text.empty?

          refuse_continuation(phase, text, number)
          return phase if text.start_with?("'")

          case phase
          when :before then before(text, number)
          when :statements then statement(builder, text, number)
          when :body then body_line(builder, text, number)
          else after(text, number)
          end
        end

        def before(text, number)
          return :statements if text == "@startuml"
          unless STARTUML.match?(text)
            raise Engine::DiagramTypeError, NOT_FOUND_MESSAGE
          end

          raise refusal(text, number, "diagram name")
        end

        def statement(builder, text, number)
          return end_of_diagram(builder, text, number) if text == "@enduml"
          raise refusal(text, number, "second diagram") if STARTUML.match?(text)

          refuse_block_comment(text, number)
          declaration_or_relation(builder, text, number)
        end

        def declaration_or_relation(builder, text, number)
          if (match = CLASS_DECLARATION.match(text))
            declare(builder, match, number, text)
          elsif (match = RELATION.match(text))
            builder.relate(relation_from(match), number, text)
            :statements
          else
            raise refusal(text, number)
          end
        end

        # PlantUML draws a welcome page, not a diagram, when nothing was
        # declared or related.
        def end_of_diagram(builder, text, number)
          raise refusal(text, number, "empty diagram") if builder.empty?

          :after
        end

        def declare(builder, match, number, text)
          kind = KINDS.fetch(match[1].split.join(" "))
          builder.declare(match[2], kind, number, text, body: !match[3].nil?)
          match[3] ? :body : :statements
        end

        def body_line(builder, text, number)
          return :statements if text == "}"
          raise unclosed_body(builder) if text == "@enduml"
          raise refusal(text, number, "second diagram") if STARTUML.match?(text)

          refuse_block_comment(text, number)
          member = member_from(text)
          raise refusal(text, number, scope: :member) unless member

          builder.add_member(member)
          :body
        end

        # PlantUML drops a /' ... '/ comment wherever it sits in a line, so a
        # field type or label read as written would still carry the comment.
        def refuse_block_comment(text, number)
          raise refusal(text, number, "block comment") if text.include?("/'")
        end

        # A trailing backslash joins the next line onto this one, even on a
        # comment, so a line-by-line read would see structure PlantUML does not.
        def refuse_continuation(phase, text, number)
          return unless text.end_with?("\\")

          case phase
          when :statements, :body
            raise refusal(text, number, "line continuation")
          end
        end

        def after(text, number)
          raise refusal(text, number, "second diagram") if STARTUML.match?(text)

          raise refusal(text, number, "content after @enduml")
        end

        def finish(phase, builder)
          case phase
          when :before then raise Engine::DiagramTypeError, NOT_FOUND_MESSAGE
          when :after then builder.diagram
          when :body then raise unclosed_body(builder)
          else
            raise Sirena::Parser::ParseError,
                  "Parse error: missing @enduml before the end of the source"
          end
        end

        def unclosed_body(builder)
          name, number = builder.open_class
          Sirena::Parser::ParseError.new(
            "Parse error: the body of class #{name} (opened on line " \
            "#{number}) is never closed with }",
          )
        end

        # The error for a line the subset does not read. `construct` names it
        # when the caller already knows what it is; otherwise the line is
        # classified.
        def refusal(text, number, construct = nil, scope: :statement)
          name = construct || UnsupportedConstructs.name_for(text, scope)
          UnsupportedConstructError.new(construct: name, line: number,
                                        text: text)
        end

        def relation_from(match)
          Relation.new(left: match[1], right: match[5],
                       arrow: ARROWS.fetch(match[3]),
                       multiplicities: { left: match[2], right: match[4] },
                       label: match[6])
        end

        # nil for anything the subset does not read. A modifier, separator or
        # stereotype is checked first because NAME alone would swallow `__`
        # and the type text would swallow a trailing `{static}`.
        def member_from(text)
          return if UnsupportedConstructs.member_construct(text)

          if (match = METHOD.match(text))
            Member.new(kind: :method, visibility: VISIBILITY[match[1]],
                       name: match[2], type: match[4], parameters: match[3])
          elsif (match = FIELD.match(text))
            Member.new(kind: :field, visibility: VISIBILITY[match[1]],
                       name: match[2], type: match[3], parameters: nil)
          end
        end
      end
    end
  end
end
