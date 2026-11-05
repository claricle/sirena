# frozen_string_literal: true

require_relative "../../error"
require_relative "../../error/diagram_type_error"
require_relative "../../error/parse_error"
require_relative "arrow"
require_relative "caption"
require_relative "class_name"
require_relative "diagram_builder"
require_relative "directives"
require_relative "junction"
require_relative "member"
require_relative "package"
require_relative "package_color"
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
        NAME = /[A-Za-z_][A-Za-z0-9_$]*/
        VISIBILITY = { "+" => :public, "-" => :private, "#" => :protected,
                       "~" => :package }.freeze
        KINDS = { "class" => :class, "abstract class" => :abstract,
                  "abstract" => :abstract, "enum" => :enum,
                  "annotation" => :annotation,
                  "interface" => :interface, "static class" => :class }.freeze

        # Every quantified piece is separated from the next by a character
        # it cannot also match, so no line backtracks more than linearly.
        STARTUML = /\A@startuml(?![A-Za-z0-9_])/
        STEREOTYPE = /<<[^<>]+>>/
        CLASS_DECLARATION =
          /\A(abstract[ \t]+class|static[ \t]+class|abstract|class|interface|
            enum|annotation)
           [ \t]+(#{NAME})
           (?:<([^<>]+)>)?((?:[ \t]*#{STEREOTYPE})*)
           ((?:[ \t]+\$#{NAME})*)(?:[ \t]+\#\S+)?(?:[ \t]*(\{))?\z/xo
        PACKAGE = /\A(\+)?package[ \t]+
                   (?:"([^"]+)"[ \t]+as[ \t]+(#{NAME})|
                      (#{NAME}(?:\.#{NAME})*))
                   (?:[ \t]*<<([^<>]+)>>)?(?:[ \t]+(\#[A-Za-z0-9]+))?
                   [ \t]*\{\z/xio
        QUOTED_DECLARATION =
          /\A(abstract[ \t]+class|static[ \t]+class|class|interface)
           [ \t]+"([^"]+)"\z/xo
        QUOTED_NAME = '"[^"]+"'
        HIDE_TAG = /\Ahide[ \t]+\$(#{NAME})\z/io
        NOTE = /\Anote[ \t]+(left|right|top|bottom)[ \t]+of[ \t]+(#{NAME})
                (?:::(#{NAME}|"[^"]+"))?(?:[ \t]+(\#[A-Za-z0-9]+))?
                (?:[ \t]*(#{STEREOTYPE}))?(?:[ \t]*:[ \t]*(.+))?\z/xio
        FREE_NOTE = /\Anote[ \t]+as[ \t]+(#{NAME})\z/i
        MEMBER_OF = /\A(#{NAME})[ \t]*:[ \t]*(\S.*)\z/o
        LAST_NOTE = /\Anote[ \t]+(left|right|top|bottom)
                     (?:[ \t]*:[ \t]*(.+))?\z/xi
        END_NOTE = /\Aend[ \t]?note\z/i
        END_TEXT = '(?:"([^"]+)"(?:/"([^"]+)")?|/"([^"]+)"|(\[[^\]]+\]))'
        RELATION = /\A(#{NAME}|#{QUOTED_NAME})[ \t]+(?:#{END_TEXT}[ \t]+)?
                    #{Arrow::PATTERN}
                    [ \t]*(?:#{END_TEXT}[ \t]+)?(#{NAME}|#{QUOTED_NAME})
                    (?:[ \t]*:[ \t]*(.+))?\z/xo
        JUNCTION = /\A\((#{NAME})[ \t]*,[ \t]*(#{NAME})\)[ \t]*
                    \.{1,2}[ \t]*(#{NAME})\z/xo
        METHOD = /\A([+\-#~])?[ \t]*(#{NAME})[ \t]*\(([^()]*)\)
                  (?:([ \t]*:[ \t]*)(.+))?\z/xo
        FIELD = /\A([+\-#~])?[ \t]*(#{NAME})(?:([ \t]*:[ \t]*)([^()]+))?\z/o
        TYPE = /#{NAME}(?:\[\])*/o
        TYPED_FIELD = /\A([+\-#~])?[ \t]*(#{TYPE})[ \t]+(#{NAME})\z/o
        TYPED_METHOD = /\A([+\-#~])?[ \t]*(#{TYPE})[ \t]+(#{NAME})[ \t]*
                        \(([^()]*)\)\z/xo
        MODIFIER = /\{(?:static|abstract|field|method)\}/i
        SEPARATOR = /\A([-=._])\1(?:[ \t]*(\S.*?)[ \t]*\1\1)?\z/
        INLINE_MARKUP = /<img:[^>]*>/i
        PLAIN_TEXT = /\A[\p{Alnum}\[][^<>{}"!$():@;]*\z/
        STYLE_OPEN = %r{\A<style>\z}i
        SKIN_BLOCK = /\Askinparam[ \t]+\S+[ \t]*\{\z/i
        LINE_END = /\r\n|\r|\n/
        NOT_FOUND_MESSAGE = "Unable to detect diagram type from source. " \
                            "Source must start with one of: @startuml"

        private_constant :NAME, :VISIBILITY, :KINDS, :STARTUML, :END_TEXT,
                         :STEREOTYPE, :CLASS_DECLARATION, :LAST_NOTE,
                         :QUOTED_DECLARATION, :QUOTED_NAME, :HIDE_TAG, :PACKAGE,
                         :NOTE, :END_NOTE,
                         :RELATION, :JUNCTION, :METHOD, :FIELD,
                         :TYPED_FIELD, :TYPED_METHOD, :MODIFIER, :TYPE,
                         :SEPARATOR, :PLAIN_TEXT, :INLINE_MARKUP, :FREE_NOTE,
                         :MEMBER_OF,
                         :STYLE_OPEN, :SKIN_BLOCK, :LINE_END, :NOT_FOUND_MESSAGE

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

        def comment?(phase, text)
          text.start_with?("'") && !%i[note style].include?(phase)
        end

        def step(phase, builder, text, number)
          return phase if text.empty?

          refuse_continuation(phase, text, number)
          return phase if comment?(phase, text)
          return (text == "}" ? :statements : :skin) if phase == :skin

          read_line(phase, builder, text, number)
        end

        def read_line(phase, builder, text, number)
          case phase
          when :before then before(text, number)
          when :statements then statement(builder, text, number)
          when :body then body_line(builder, text, number)
          when :note then note_line(builder, text, number)
          when :style then style_line(builder, text, number)
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
          # The block's lines are read by Style::Reader, not here.
          return :skin if SKIN_BLOCK.match?(text)
          return record(builder, text) if Directives.match?(text)

          line_statement(builder, text, number)
        end

        def line_statement(builder, text, number)
          caption_or_style(builder, text, number) ||
            block_line(builder, text, number) ||
            quoted_declaration(builder, text, number) ||
            declaration_or_relation(builder, text, number)
        end

        # nil unless the line is a caption or opens a style block.
        def caption_or_style(builder, text, number)
          if (caption = Caption.read(text))
            builder.caption(caption)
            :statements
          elsif STYLE_OPEN.match?(text)
            builder.open_style(number, text)
            :style
          end
        end

        def style_line(builder, text, number)
          raise unclosed_style(builder) if text == "@enduml"

          builder.style_line(text, number) == :closed ? :statements : :style
        end

        # nil unless the line hides a tag or opens or closes a package.
        def block_line(builder, text, number)
          if HIDE_TAG.match?(text)
            hide_tag(builder, text, number)
          elsif PACKAGE.match?(text)
            open_package(builder, text, number)
          elsif text == "}" && builder.package_open?
            close_package(builder)
          end
        end

        def close_package(builder)
          builder.close_package
          :statements
        end

        def open_package(builder, text, number)
          package = package_from(PACKAGE.match(text), text, number)
          builder.open_package(package, number, text)
          :statements
        end

        def package_from(match, text, number)
          shape = package_shape(match[5])
          raise refusal(text, number, "package stereotype") unless shape

          Package.new(id: match[3] || match[4], title: package_title(match),
                      shape: shape, icon: !match[1].nil?,
                      color: package_color(match[6], text, number))
        end

        # A dotted name is drawn as its last part, inside a frame for each
        # part before it.
        def package_title(match)
          match[2] || match[4].split(".").last
        end

        def package_color(written, text, number)
          return unless written

          PackageColor.hex(written) ||
            raise(refusal(text, number, "package colour name"))
        end

        def package_shape(stereotype)
          return :folder unless stereotype

          :frame if stereotype.casecmp?("frame")
        end

        def hide_tag(builder, text, number)
          builder.hide_tag(HIDE_TAG.match(text)[1], number, text)
          :statements
        end

        def record(builder, text)
          builder.directive(text)
          :statements
        end

        def declaration_or_relation(builder, text, number)
          if (match = CLASS_DECLARATION.match(text))
            declare(builder, match, number, text)
          elsif (match = JUNCTION.match(text))
            junction(builder, match, number, text)
          elsif (match = NOTE.match(text))
            note(builder, match, number, text)
          else
            last_note_or_relation(builder, text, number)
          end
        end

        def last_note_or_relation(builder, text, number)
          return free_note(builder, number) if FREE_NOTE.match?(text)

          match = LAST_NOTE.match(text)
          return last_note(builder, match, number, text) if match

          member_statement(builder, text, number) ||
            relation(builder, text, number)
        end

        # `Name : text` adds a line to the class, declaring it when new.
        def member_statement(builder, text, number)
          match = MEMBER_OF.match(text)
          return if match.nil? || RELATION.match?(text)

          member = member_from(match[2])
          raise refusal(text, number, scope: :member) unless member

          builder.add_member_to(match[1], member)
          :statements
        end

        # `note as N1` floats beside the classes, attached to none of them.
        def free_note(builder, number)
          head = { side: :free, target: nil, member: nil, color: nil,
                   stereotype: nil }
          builder.open_note(head, number, [])
          :note
        end

        # A note with `: text` is one line; without it the text follows up
        # to `end note`. PlantUML refuses `::member` with inline text.
        def note(builder, match, number, text)
          head = note_head(match)
          inline = match[6]&.then { |line| plain_note_text(line) }
          raise refusal(text, number) if inline && head[:member]

          builder.open_note(head, number, [*inline])
          return :note unless inline

          builder.close_note
          :statements
        end

        # `note left: text` sits beside the class defined last.
        def last_note(builder, match, number, text)
          target = builder.last_defined
          raise refusal(text, number) unless target

          head = { side: match[1].downcase.to_sym, target: target,
                   member: nil, color: nil, stereotype: nil }
          inline = match[2]&.then { |line| plain_note_text(line) }
          builder.open_note(head, number, [*inline])
          return :note unless inline

          builder.close_note
          :statements
        end

        def note_head(match)
          { side: match[1].downcase.to_sym, target: match[2],
            member: match[3], color: match[4], stereotype: match[5] }
        end

        def note_line(builder, text, number)
          if END_NOTE.match?(text)
            builder.close_note
            return :statements
          end
          refuse_note_text(builder, text, number)
          builder.add_note_line(plain_note_text(text))
          :note
        end

        # Creole tags stay for the renderer; `<img:>` has no drawn form
        # here and is dropped.
        def plain_note_text(text)
          text.gsub(INLINE_MARKUP, "").squeeze(" ")
        end

        def junction(builder, match, number, text)
          builder.junction(Junction.new(**junction_names(match)), number, text)
          :statements
        end

        def junction_names(match)
          { from: match[1], to: match[2], owner: match[3] }
        end

        def relation(builder, text, number)
          match = RELATION.match(text)
          arrow = match && Arrow.parse(match[6])
          raise refusal(text, number, both_arrowheads(match)) unless arrow

          builder.relate(relation_from(match, arrow), number, text)
          :statements
        end

        # A matched relation with no arrow has an arrowhead on each end.
        def both_arrowheads(match)
          "relation <-> arrow" if match
        end

        # PlantUML draws a welcome page, not a diagram, when nothing was
        # declared or related.
        def end_of_diagram(builder, text, number)
          raise refusal(text, number, "empty diagram") if builder.empty?
          raise unclosed_package(builder) if builder.open_package_line

          :after
        end

        def declare(builder, match, number, text)
          entry = declaration_entry(match)
          builder.declare(entry, number, text)
          entry[:body] ? :body : :statements
        end

        # nil unless the line declares a class by a quoted name.
        def quoted_declaration(builder, text, number)
          match = QUOTED_DECLARATION.match(text)
          return unless match

          if ClassName.escapes?(match[2])
            raise refusal(text, number, "unicode escape in a name")
          end

          builder.declare(quoted_entry(match), number, text)
          :statements
        end

        def quoted_entry(match)
          { name: match[2], kind: KINDS.fetch(match[1].split.join(" ")),
            body: false, generics: nil, stereotypes: [].freeze,
            tags: [].freeze }
        end

        def declaration_entry(match)
          { name: match[2], kind: KINDS.fetch(match[1].split.join(" ")),
            body: !match[6].nil?, generics: match[3],
            stereotypes: stereotypes_of(match[4]),
            tags: match[5].scan(/\w+/).freeze }
        end

        def stereotypes_of(text)
          text.scan(STEREOTYPE).map { |tag| tag[2..-3] }.freeze
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
          when :statements, :body, :note, :style
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
          when :note then raise unclosed_note(builder)
          when :style then raise unclosed_style(builder)
          else
            raise Sirena::Parser::ParseError,
                  "Parse error: missing @enduml before the end of the source"
          end
        end

        def refuse_note_text(builder, text, number)
          raise unclosed_note(builder) if text == "@enduml"
          if text.start_with?("'")
            raise refusal(text, number, "comment in a note")
          end

          refuse_block_comment(text, number)
        end

        def unclosed_note(builder)
          Sirena::Parser::ParseError.new(
            "Parse error: the note opened on line " \
            "#{builder.open_note_line} is never closed with end note",
          )
        end

        def unclosed_style(builder)
          Sirena::Parser::ParseError.new(
            "Parse error: the style block opened on line " \
            "#{builder.open_style_line} is never closed with </style>",
          )
        end

        def unclosed_package(builder)
          Sirena::Parser::ParseError.new(
            "Parse error: the package opened on line " \
            "#{builder.open_package_line} is never closed with }",
          )
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

        def relation_from(match, arrow)
          Relation.new(left: unquoted(match[1]), right: unquoted(match[11]),
                       arrow: arrow,
                       ends: end_texts(match), label: match[12])
        end

        def unquoted(name)
          name.delete_prefix('"').delete_suffix('"')
        end

        def end_texts(match)
          { left: match[2] || match[5], left_role: match[3] || match[4],
            right: match[7] || match[10], right_role: match[8] || match[9] }
        end

        # nil for anything the subset does not read. A separator is checked
        # first because NAME alone would swallow `__`; modifiers are lifted
        # out of the line wherever they sit, as PlantUML reads them.
        def member_from(text)
          separator = SEPARATOR.match(text)
          return separator_member(separator) if separator
          return if UnsupportedConstructs.member_construct(text)

          modified_member(text)
        end

        def modified_member(text)
          words = text.scan(MODIFIER).map { |word| word.delete("{}").downcase }
          rest = text.gsub(MODIFIER, " ").squeeze(" ").strip
          member = named_member(rest) || typed_member(rest) || text_member(rest)
          words.empty? || member.nil? ? member : lifted(member, words)
        end

        def lifted(member, words)
          return if words.include?("field") && contradicts_field?(words, member)

          retype(member, words)
        end

        # `.. title ..`, `== title ==`, `__ title __` and `-- title --`: a rule
        # across the compartment, its title (if any) in the middle.
        def separator_member(match)
          Member.new(kind: :separator, visibility: nil, name: match[2].to_s,
                     type: match[1])
        end

        # Any other plain line of a class body is shown as written.
        def text_member(text)
          return unless PLAIN_TEXT.match?(text)

          Member.new(kind: :field, visibility: nil, name: text, type: nil,
                     parameters: nil)
        end

        def contradicts_field?(words, member)
          words.include?("method") || member.parameters
        end

        def named_member(text)
          if (match = METHOD.match(text))
            suffixed(:method, match, 5, parameters: match[3])
          elsif (match = FIELD.match(text))
            suffixed(:field, match, 4)
          end
        end

        # A member whose type follows a colon; the group before the type
        # holds the colon with the spacing written around it.
        def suffixed(kind, match, type_group, parameters: nil)
          Member.new(kind: kind, visibility: VISIBILITY[match[1]],
                     name: match[2], type: match[type_group],
                     parameters: parameters,
                     type_separator: match[type_group - 1] || ": ")
        end

        def retype(member, words)
          modifiers = (words & %w[abstract static]).map(&:to_sym).freeze
          kind = words.include?("method") ? :method : member.kind
          Member.new(kind: kind, visibility: member.visibility,
                     name: member.name, type: member.type,
                     parameters: member.parameters, modifiers: modifiers,
                     type_position: member.type_position,
                     type_separator: member.type_separator)
        end

        # `int x` and `void run(int a)`: the type comes first.
        def typed_member(text)
          if (match = TYPED_METHOD.match(text))
            Member.new(kind: :method, visibility: VISIBILITY[match[1]],
                       name: match[3], type: match[2], parameters: match[4],
                       type_position: :prefix)
          elsif (match = TYPED_FIELD.match(text))
            Member.new(kind: :field, visibility: VISIBILITY[match[1]],
                       name: match[3], type: match[2], parameters: nil,
                       type_position: :prefix)
          end
        end
      end
    end
  end
end
