# frozen_string_literal: true

require_relative 'common'
require_relative 'mermaid_unicode_text'

module Sirena
  module Parser
    module Grammars
      # Parslet grammar for Class diagrams.
      #
      # Handles UML class diagram syntax including classes, attributes,
      # methods, relationships with various types (inheritance, composition,
      # aggregation, association, dependency, realization), stereotypes,
      # generic types, namespaces, and cardinality labels.
      class ClassDiagram < Common
        # A two-way relation's per-end marker glyph, per mermaid's own
        # structural grammar [Relation Type][Link][Relation Type]
        # (https://mermaid.js.org/syntax/classDiagram#two-way-relations).
        # `<|`/`|>` must sort before `<`/`>` below (MIXED_OPERATOR_STRINGS)
        # so the two-char glyph wins over its one-char prefix.
        TWO_WAY_MARKERS = ['<|', '|>', '*', 'o', '<', '>'].freeze

        # The two link styles a two-way relation can use.
        TWO_WAY_LINKS = ['--', '..'].freeze

        # Every [marker][link][marker] combination mermaid's structural
        # grammar allows, longest-string-first so `<|--|>` is matched whole
        # rather than as the shorter `<--|>`-shaped prefix a 1-char marker
        # alternative could otherwise claim.
        MIXED_OPERATOR_STRINGS = TWO_WAY_MARKERS
          .product(TWO_WAY_LINKS, TWO_WAY_MARKERS)
          .map { |left, link, right| "#{left}#{link}#{right}" }
          .sort_by { |operator| -operator.length }
          .freeze

        root(:diagram)

        # Main diagram structure
        rule(:diagram) do
          ws? >>
            header >>
            ws? >>
            statements.maybe >>
            ws?
        end

        # `classDiagram-v2` is the same language; mmdc takes no direction on
        # its header line (`classDiagram-v2 LR` is rejected). Neither header
        # line takes a trailing `%%` comment either — mmdc rejects
        # `classDiagram %%x` and `classDiagram-v2 %%x` just as it rejects a
        # direction there.
        rule(:header) do
          (str('classDiagram-v2').as(:header) >>
            space? >> (newline | eof).present? >> ws?) |
            (str('classDiagram').as(:header) >> header_end >>
              space? >> direction_value.maybe.as(:direction) >> space? >>
              (newline | eof).present? >> ws?)
        end

        # `classDiagramX` is not a header, and the line ends after the header:
        # `classDiagram `A`` is rejected by mmdc.
        rule(:header_end) do
          (name_char | str('-')).absent?
        end

        rule(:direction_value) do
          (str("TD") | str("TB") | str("LR") | str("RL") | str("BT")).as(:dir_value)
        end

        rule(:direction) do
          direction_value >> ws?
        end

        rule(:statements) do
          (statement >> ws?).repeat(1)
        end

        # acc* come first: `accTitle: My Title` also reads as a colon member
        # definition on a class named accTitle.
        rule(:statement) do
          acc_title_statement |
            acc_descr_statement |
            namespace_block |
            class_declaration |
            standalone_stereotype |
            colon_member_definition |
            relationship |
            link_statement |
            callback_statement |
            click_statement |
            style_statement |
            css_class_statement |
            class_def_statement |
            direction_statement |
            note_statement |
            standalone_class
        end

        # Namespace block: namespace Name { ... }
        rule(:namespace_block) do
          str('namespace').as(:namespace_keyword) >> space >>
            namespace_name.as(:namespace_name) >> space? >>
            lbrace >> ws? >>
            namespace_statements.maybe.as(:namespace_body) >>
            ws? >> rbrace >>
            line_end
        end

        rule(:namespace_name) do
          (match['a-zA-Z0-9_.'] | str('-')).repeat(1)
        end

        rule(:namespace_statements) do
          (namespace_statement >> ws?).repeat(1)
        end

        rule(:namespace_statement) do
          class_declaration |
            standalone_stereotype |
            colon_member_definition |
            relationship |
            standalone_class
        end

        # Class declaration: class ClassName <<stereotype>> { body }
        # Clause order follows mermaid: id, generic, label, stereotype, body.
        #
        # Generic and stereotype used to be the other way round, which made
        # sirena accept `class C1<<iface>>~T~` (mmdc rejects it) and reject
        # `class C1~T~<<iface>>` (mmdc accepts it). Swapping them is also what
        # gives the text label exactly one home rather than two.
        rule(:class_declaration) do
          str('class').as(:keyword) >> space >>
            class_name.as(:class_id) >> space? >>
            generic_params.maybe.as(:generic) >> space? >>
            text_label.maybe.as(:text_label) >> space? >>
            (css_shorthand | stereotype.maybe.as(:stereotype)) >> space? >>
            class_body.maybe.as(:body) >>
            line_end
        end

        # `class C1:::pink`. mmdc rejects it together with a stereotype, in
        # either order, and rejects a label after it, so it is an alternative
        # to the stereotype slot rather than a slot of its own.
        rule(:css_shorthand) do
          str(':::') >> space? >> name_char.repeat(1).as(:css_class)
        end

        # `class C1["Label"]` only, matching mmdc 11.12.0 exactly.
        #
        # Two forms are deliberately NOT accepted, both verified against the
        # oracle: `class C1[]` (mmdc: "Expecting 'STR', got 'SQE'") and
        # `class C1['Label']` (mmdc: "Expecting 'STR', got 'PUNCTUATION'").
        # 20 corpus cases use the empty form and none carries a sidecar; their
        # test names say "should parse a class with a text label", so the label
        # content was lost in extraction. Accepting it would be over-acceptance
        # against a damaged input.
        #
        # quoted_string rather than common.rb's `string`, because `string`
        # admits single quotes. It still swallows a nested bracket correctly:
        # `class C4["With [Brackets]"]`.
        rule(:text_label) do
          lbracket >> space? >> label_string >> space? >> rbracket
        end

        # A label-local string, NOT common.rb's quoted_string.
        #
        # Two differences, both measured against mmdc 11.12.0:
        #   - space? inside the brackets, because `class C1[ "L" ]` renders.
        #   - no backslash-escape branch. common.rb's quoted_string has
        #     `str('\\') >> any`, which swallows `\"` and made us accept
        #     `class C1["a\"b"]`; mmdc rejects that with
        #     "Expecting 'SQE', got 'ALPHA'".
        #
        # Defined here rather than by changing quoted_string, which 15
        # grammars share.
        rule(:label_string) do
          str('"') >> (str('"').absent? >> any).repeat.as(:string) >> str('"')
        end

        # Standalone stereotype: <<interface>> ClassName
        rule(:standalone_stereotype) do
          stereotype.as(:stereotype) >> space >>
            class_name.as(:class_id) >>
            line_end
        end

        # Colon member definition: ClassName : +member or ClassName : +method()
        #
        # Anything after the colon is a member to mmdc; text the structured
        # rules do not read is kept whole (`Car : +ArrayList size()`), except
        # that a second `:` or a `;` is a syntax error (`A:::s`, `A : x:y`).
        rule(:colon_member_definition) do
          class_ref >> space? >>
            colon >> space? >>
            (colon_body_annotation >> line_end |
              (visibility_modifier.maybe.as(:visibility) >>
                member_definition.as(:member) >> line_end) |
              colon_text.as(:raw_member) >> line_end)
        end

        # Link statement: link ClassName "url" "tooltip"
        rule(:link_statement) do
          str('link').as(:link_keyword) >> space >>
            class_name.as(:class_id) >> space >>
            string.as(:url) >>
            (space >> string.as(:tooltip)).maybe >>
            line_end
        end

        # Callback statement: callback ClassName "function" "tooltip"
        rule(:callback_statement) do
          str('callback').as(:callback_keyword) >> space >>
            class_name.as(:class_id) >> space >>
            string.as(:callback_fn) >>
            (space >> string.as(:tooltip)).maybe >>
            line_end
        end

        # Rest of the line, up to the statement terminator.
        rule(:rest_of_line) do
          (line_end.absent? >> any).repeat(1)
        end

        # click ClassName href "url" ["tooltip"] [target]
        # click ClassName call fn(args) ["tooltip"]
        #
        # Parsed and dropped, like link and callback: the model has no
        # interaction data and mmdc renders click targets as plain classes.
        # The remainder is not parsed because the corpus carries forms with
        # the URL missing (`click Class1 href`) that mmdc still renders.
        rule(:click_statement) do
          str("click").as(:ignored) >> space >>
            class_name >>
            (space >> rest_of_line).maybe >>
            line_end
        end

        # style ClassName fill:#f9f,stroke:#333
        rule(:style_statement) do
          str("style").as(:ignored) >> space >>
            class_name >> space >> rest_of_line >>
            line_end
        end

        # cssClass "A,B" styleName
        rule(:css_class_statement) do
          str("cssClass").as(:ignored) >> space >>
            rest_of_line >>
            line_end
        end

        # classDef name key:value,key:value
        rule(:class_def_statement) do
          str("classDef").as(:ignored) >> space >>
            rest_of_line >>
            line_end
        end

        # direction TB, inside the diagram (the header takes one too)
        rule(:direction_statement) do
          str("direction").as(:direction_keyword) >> space >>
            direction_value >> line_end
        end

        # accTitle: single line
        rule(:acc_title_statement) do
          str("accTitle").as(:ignored) >> space? >>
            colon >> rest_of_line.maybe >> line_end
        end

        # accDescr: single line   |   accDescr { multiple lines }
        rule(:acc_descr_statement) do
          str("accDescr").as(:ignored) >> space? >>
            ((colon >> rest_of_line.maybe) |
              (lbrace >> (rbrace.absent? >> any).repeat >> rbrace)) >>
            line_end
        end

        # note "text"   |   note for ClassName "text"
        #
        # The text runs to the end of the line rather than to the closing
        # quote because the corpus has notes with quotes inside HTML.
        rule(:note_statement) do
          str("note").as(:ignored) >>
            (space >> str("for") >> space >> class_name).maybe >>
            space >> rest_of_line >>
            line_end
        end

        # Standalone class (just an identifier)
        rule(:standalone_class) do
          class_ref >> line_end
        end

        # A class name with the generic mmdc lets follow it on a standalone
        # class, a colon member and a relationship end: `Class1~T~ <|-- Class02`,
        # `Car~T~ : +wheels`.
        rule(:class_ref) do
          class_name.as(:class_id) >> generic_suffix.as(:generic)
        end

        rule(:from_generic) { generic_suffix.as(:from_generic) }
        rule(:to_generic) { generic_suffix.as(:to_generic) }

        rule(:generic_suffix) do
          (space? >> generic_params).maybe
        end

        # A word character in a class name or a CSS class: ASCII letters and
        # digits, underscore, and the letters in mermaid's own table
        # (`MERMAID_UNICODE_TEXT`). mmdc accepts `class 1` and `class é`, and
        # rejects `class ١` (a non-ASCII digit) and `class 𐐀` (an astral
        # letter, absent from the table).
        rule(:name_char) do
          match["A-Za-z0-9_#{MERMAID_UNICODE_TEXT}"]
        end

        # Class name: words joined by a single `.` (namespace-qualified) or a
        # single interior `-` (`Ca-r`), or backtick-quoted (`` `A B` ``).
        # A `-` that is not followed by a word character is the start of an
        # operator (`A-->B`), so it ends the name. mmdc rejects `A.`, `.A`
        # and `A..B` as names.
        #
        # The backticks stay in the parse tree; the transform strips them so
        # `Car` and `` `Car` `` are one class.
        rule(:class_name) do
          backtick_name | plain_class_name
        end

        rule(:backtick_name) do
          str('`') >> (str('`').absent? >> any).repeat(1) >> str('`')
        end

        rule(:plain_class_name) do
          hyphenated_word >> (str('.') >> hyphenated_word).repeat
        end

        rule(:hyphenated_word) do
          name_char.repeat(1) >> (str('-') >> name_char.repeat(1)).repeat
        end

        # Stereotype: <<interface>>, <<abstract>>, etc.
        rule(:stereotype) do
          str('<<') >>
            (str('>>').absent? >> any).repeat(1).as(:stereotype_value) >>
            str('>>')
        end

        # Generic parameters: ~T~ or ~Type~
        rule(:generic_params) do
          tilde >>
            (tilde.absent? >> any).repeat(1).as(:generic_type) >>
            tilde
        end

        # Class body: { members }
        rule(:class_body) do
          lbrace >> body_gap >>
            class_members.maybe >>
            ws? >> rbrace
        end

        rule(:class_members) do
          (class_member >> body_gap).repeat(1)
        end

        # Blank lines and comments between members. The indentation of the
        # next member is left unread: mmdc rejects a line that STARTS with a
        # quote but accepts an indented one as the member ` "quoted"`.
        rule(:body_gap) do
          (space.repeat >> (newline | comment)).repeat
        end

        # A body line is an annotation, a structured member, or free text.
        # mmdc reads every line that is none of the first two as a member, so
        # `void methods()` and `.. Getters ..` are members. It rejects only a
        # `{` inside the text and a line that starts with a quote.
        rule(:class_member) do
          (space.repeat(1) >> indented_quote_text.as(:raw_member)) |
            (space? >>
              (body_annotation |
                (visibility_modifier.maybe.as(:visibility) >>
                  member_definition.as(:member) >> member_end) |
                body_text.as(:raw_member)))
        end

        rule(:indented_quote_text) do
          str('"') >> body_char.repeat >> member_end
        end

        # `<<interface>>` on its own line. mmdc takes a line that starts with
        # `<<` and ends with `>>`, so the last `>>` closes it:
        # `<<a>>b>>` is the annotation `a>>b`.
        rule(:body_annotation) do
          str('<<') >>
            (annotation_text.as(:body_stereotype) |
              str('').as(:body_stereotype)) >>
            str('>>') >> member_end
        end

        rule(:annotation_text) do
          ((str('>>') >> member_end).absent? >> body_char).repeat(1)
        end

        # Same shape as body_annotation, for the colon-member form
        # (`ClassName : <<interface>>`). A `:` or `;` inside still ends the
        # member early there, the same ban colon_text enforces: mmdc rejects
        # `A : <<a;b>>` and `A : <<a:b>>`.
        rule(:colon_body_annotation) do
          str('<<') >>
            (colon_annotation_text.as(:body_stereotype) |
              str('').as(:body_stereotype)) >>
            str('>>') >> member_end
        end

        rule(:colon_annotation_text) do
          ((str('>>') >> member_end).absent? >> match[':;'].absent? >> body_char).repeat(1)
        end

        rule(:colon_text) do
          (match[":;\n"].absent? >> line_end.absent? >> any).repeat(1)
        end

        # A `%%` starts a trailing comment mmdc strips, same as line_end does
        # outside the body; free-text member capture must stop there instead
        # of swallowing the comment as member text.
        rule(:body_char) do
          (str('%%') | match["\n{}"]).absent? >> any
        end

        rule(:body_text) do
          (str('"').absent? >> body_char) >> body_char.repeat >> member_end
        end

        # A member ends at the line break, the `}` that closes the body, or
        # a trailing `%%` comment — a pure lookahead, same as before: the
        # comment itself is left for body_gap to consume between members, so
        # it never ends up inside a member capture that wraps this rule.
        rule(:member_end) do
          space? >> (comment | newline | rbrace | eof).present?
        end

        # Member definition (attribute or method)
        rule(:member_definition) do
          method_definition | attribute_definition
        end

        # Method: name(params) or name(params): returnType
        rule(:method_definition) do
          method_name.as(:method_name) >>
            lparen >>
            method_params.maybe.as(:parameters) >>
            rparen >>
            method_return_type.maybe.as(:return_type)
        end

        rule(:method_name) do
          identifier
        end

        rule(:method_params) do
          (rparen.absent? >> any).repeat(1)
        end

        rule(:method_return_type) do
          space? >> colon >> space? >>
            type_expression.as(:type)
        end

        # Attribute: type name or name: type
        rule(:attribute_definition) do
          # Try type-first format: type name
          (type_expression.as(:type) >> space >> identifier.as(:attr_name)) |
            # Try name-first with optional type: name or name: type
            (identifier.as(:attr_name) >>
              (space? >> colon >> space? >> type_expression.as(:type)).maybe)
        end

        # Type expression (handles generics like List~String~)
        rule(:type_expression) do
          match['a-zA-Z_'] >> match['a-zA-Z0-9_<>'].repeat >>
            (tilde >> (tilde.absent? >> any).repeat >> tilde).maybe
        end

        # Visibility modifiers
        rule(:visibility_modifier) do
          (plus | minus | hash_char | tilde).as(:vis_symbol)
        end

        # Relationship: A relationship_operator B
        rule(:relationship) do
          class_name.as(:from_id) >> from_generic >> space? >>
            source_cardinality.maybe.as(:source_card) >> space? >>
            relationship_operator.as(:operator) >> space? >>
            pipe_label.maybe.as(:pipe_label) >> space? >>
            target_cardinality.maybe.as(:target_card) >> space? >>
            class_name.as(:to_id) >> to_generic >>
            colon_label.maybe.as(:colon_label) >>
            line_end
        end

        # Cardinality: "1", "*", "0..1", "1..*", etc.
        rule(:source_cardinality) do
          string
        end

        rule(:target_cardinality) do
          string
        end

        # Relationship operators (8 types, plus mixed-marker combos where the
        # two ends carry different structural markers, e.g. `o--|>`)
        rule(:relationship_operator) do
          mixed_operator |
            inheritance_operator |
            composition_operator |
            aggregation_operator |
            realization_operator |
            dependency_operator |
            association_operator
        end

        # mermaid allows independent markers on each end of a relation
        # (e.g. aggregation `o` on one side, extension `|>` on the other),
        # structurally [Relation Type][Link][Relation Type] -- mermaid's own
        # documented example is `Animal <|--|> Zebra`. Generated from
        # MIXED_OPERATOR_STRINGS instead of one literal per combination, so
        # a not-yet-seen pairing parses without a new hardcoded string.
        # `o..` (a marker on one side only, no counterpart) is not a
        # two-way relation and is kept as its own literal.
        # These must be tried before the single-sided operators below,
        # which would otherwise match a short prefix and strand the
        # remaining marker character.
        rule(:mixed_operator) do
          (MIXED_OPERATOR_STRINGS.map { |operator| str(operator) }.reduce(:|) |
            str('o..')).as(:arrow)
        end

        rule(:inheritance_operator) do
          (str('<|--') | str('--|>')).as(:arrow)
        end

        rule(:composition_operator) do
          (str('*--') | str('--*')).as(:arrow)
        end

        rule(:aggregation_operator) do
          (str('o--') | str('--o')).as(:arrow)
        end

        rule(:realization_operator) do
          (str('..|>') | str('<|..')).as(:arrow)
        end

        rule(:dependency_operator) do
          (str('..>') | str('<..')).as(:arrow)
        end

        rule(:association_operator) do
          (str('-->') | str('<--') | str('--') | str('..')).as(:arrow)
        end

        # Labels
        rule(:pipe_label) do
          pipe >>
            (pipe.absent? >> any).repeat(1).as(:label_text) >>
            pipe
        end

        rule(:colon_label) do
          space? >> colon >> space? >>
            (line_end.absent? >> any).repeat(1).as(:label_text)
        end

        # Line terminators for class diagrams
        rule(:line_end) do
          semicolon.maybe >> space? >> (comment.maybe >> newline | eof)
        end
      end
    end
  end
end