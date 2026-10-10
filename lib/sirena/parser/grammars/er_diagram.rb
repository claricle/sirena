# frozen_string_literal: true

require_relative "common"

module Sirena
  module Parser
    module Grammars
      # Parslet grammar for ER diagrams.
      #
      # Handles Entity-Relationship diagram syntax including entities,
      # attributes, relationships with cardinality notation, and both
      # identifying and non-identifying relationships.
      class ErDiagram < Common
        # ECMA-262 LineTerminator: what a JS `.` refuses to cross.
        JS_LINE_TERMINATOR_CHARS = '\n\r\u2028\u2029'
        private_constant :JS_LINE_TERMINATOR_CHARS

        # ECMA-262 WhiteSpace + LineTerminator: what JS `\s` matches.
        JS_WHITESPACE_CHARS = '\t\v\f\x20\u00A0\u1680\u2000-\u200A' \
                              '\u2028\u2029\u202F\u205F\u3000\uFEFF\n\r'
        private_constant :JS_WHITESPACE_CHARS

        root(:diagram)

        # Main diagram structure
        rule(:diagram) do
          ws? >>
            header >>
            ws? >>
            statements.maybe >>
            ws?
        end

        rule(:header) do
          str("erDiagram").as(:header) >> ws?
        end

        rule(:statements) do
          (statement >> ws?).repeat(1)
        end

        rule(:statement) do
          class_def_statement |
            entity_definition |
            relationship |
            entity_declaration
        end

        # Entity with attribute block
        rule(:entity_definition) do
          entity_name.as(:entity_id) >>
            (str(":::") >> class_name_list.as(:entity_classes)).maybe >>
            space? >>
            lbrace >> ws? >>
            attributes.maybe.as(:attributes) >>
            ws? >> rbrace >>
            line_end
        end

        # An entity name as mermaid's lexer reads it: a double-quoted run
        # (quotes dropped by the builder), a number (`1`, `1.5`), or a word
        # that may contain `-`, so `ORDER-ITEM` is one entity. Digit-led
        # words such as `2abc` are not names in a relationship; mermaid
        # rejects them there, and so does this rule.
        rule(:entity_name) do
          (str('"') >> GreedyRun.new('[^"]', min: 1) >> str('"')) |
            (match["0-9"].repeat(1) >> str(".") >> match["0-9"].repeat(1)) |
            match["0-9"].repeat(1) |
            (match["a-zA-Z_"] >> match["a-zA-Z0-9_\\-"].repeat)
        end

        # Relationship between entities
        #
        # The two ends capture under DIFFERENT names. Parslet merges a
        # statement's captures into one hash, so giving both ends
        # `:entity_classes` drops the from-end silently, warning only on
        # stderr. A7 in the parser spec is the guard.
        rule(:relationship) do
          entity_name.as(:from_id) >>
            (str(":::") >> class_name_list.as(:from_classes)).maybe >>
            space? >>
            relationship_pattern.as(:pattern) >> space? >>
            entity_name.as(:to_id) >>
            (str(":::") >> class_name_list.as(:to_classes)).maybe >>
            space? >>
            relationship_label.maybe.as(:label) >>
            line_end
        end

        # Stand-alone entity (no body, no relationship)
        rule(:entity_declaration) do
          entity_name.as(:entity_id) >>
            (str(":::") >> class_name_list.as(:entity_classes)).maybe >>
            line_end
        end

        # Style class declaration: `classDef name[,name] <styles>`
        #
        # The style run ends at `line_end`, not at a newline, and `line_end`
        # opens with `semicolon.maybe` — so `classDef x fill:#f96;` captures
        # `fill:#f96` and mermaid's optional trailing `;` is not part of the
        # style text. A15 pins it.
        rule(:class_def_statement) do
          str("classDef") >> space.repeat(1) >>
            class_name_list.as(:classdef_names) >> space.repeat(1) >>
            (line_end.absent? >> any).repeat(1).as(:classdef_styles) >>
            line_end
        end

        # One or more class names. Names are the inherited `identifier`;
        # mermaid accepts more, and its `:::` and `classDef` sides disagree
        # with each other about what. See the plan's declared gap 1.
        rule(:class_name_list) do
          identifier >> (comma >> space? >> identifier).repeat
        end

        # Attributes within entity block
        rule(:attributes) do
          (attribute >> ws?).repeat(1)
        end

        rule(:attribute) do
          attribute_type.maybe.as(:type) >> space? >>
            identifier.as(:name) >> space? >>
            key_type.maybe.as(:key) >>
            (space? >> note.as(:note)).maybe >>
            (space? >> comment).maybe
        end

        # Double-quoted only, no escapes, no embedded quote -- do not widen
        # this to accept single quotes or `\"` like common.rb's `string`/
        # `single_quoted_string`; mermaid's own ER COMMENT token rejects both.
        #
        # `GreedyRun`, not `match('[^"]').repeat`: the native form folds
        # one-char Slices back together per character, which is O(n^2) on a
        # long note.
        rule(:note) do
          str('"') >> GreedyRun.new('[^"]', min: 0).as(:string) >> str('"')
        end

        # A plain identifier, or a `~...~`-quoted type for a name mermaid's
        # own identifier can't hold, like `~timestamp with time zone~`.
        rule(:attribute_type) do
          tilde_type | identifier
        end

        # Matches mermaid's lexer `/^(?:([^\s]*)[~].*[~]([^\s]*))/i`: no
        # minimum length between the tildes, `.` cannot cross a JS line
        # terminator, and a non-whitespace run may sit directly before the
        # opening tilde and after the closing one. Captures the FULL match
        # as `:string` -- the builder converts paired tildes to `<`/`>`
        # via `parse_generic_types`, it must never just strip them.
        #
        # JS `.*` is greedy: it matches to the LAST tilde on the line, not
        # the first (see spec/sirena/parser/er_diagram_spec.rb).
        # `tilde_marked_run` reproduces that.
        rule(:tilde_type) do
          (tilde_prefix >> tilde_marked_run >> tilde_suffix).as(:string)
        end

        # The `~T~` core, from the opening tilde through the LAST tilde
        # before a JS line terminator: one-or-more tilde-closed chunks,
        # `(?:[^~<lineterm>]*~)+`. Needs `DelimitedRun`, not a plain
        # `GreedyRun` -- this pattern's own trailing tilde requirement
        # cannot be decided from one chunk in isolation (a run that
        # reaches a chunk boundary might still find its closing tilde in
        # the NEXT chunk), so `DelimitedRun` matches segment-by-segment
        # instead of scanning the whole compound pattern per chunk.
        rule(:tilde_marked_run) do
          DelimitedRun.new("~", "[^~#{JS_LINE_TERMINATOR_CHARS}]")
        end

        # `[^\s]` in mermaid's lexer is JS's `\s`, which is the full
        # ECMA-262 WhiteSpace + LineTerminator set -- not just space, tab
        # and `\n`. `JS_WHITESPACE_CHARS` is the same set already used for
        # this in `lib/sirena/parser/grammars/flowchart.rb`
        # (`LINE_SPACE_CHARS`, plus `\n`/`\r` since this rule's `[^\s]`
        # excludes those too, unlike flowchart's line-space-only class).
        rule(:tilde_prefix) do
          GreedyRun.new("[^~#{JS_WHITESPACE_CHARS}]", min: 0)
        end

        rule(:tilde_suffix) do
          GreedyRun.new("[^#{JS_WHITESPACE_CHARS}]", min: 0)
        end

        rule(:key_type) do
          (str("PK") | str("FK") | str("UK")).as(:key_type)
        end

        # Relationship pattern: cardinality(2) + operator(2) + cardinality(2)
        # Examples: ||--o{, ||==|{, }o..||
        rule(:relationship_pattern) do
          cardinality.as(:card_from) >>
            operator.as(:operator) >>
            cardinality.as(:card_to)
        end

        # Cardinality symbols (2 characters)
        rule(:cardinality) do
          str("||") | str("o{") | str("|{") | str("}o") | str("}|") |
            str("o|") | str("|o") |
            str("{o") | str("{|") | str("}{") | str("{}")
        end

        # Relationship operators (2 characters)
        rule(:operator) do
          str("==") | str("--") | str("..")
        end

        # Relationship label (after colon)
        rule(:relationship_label) do
          colon >> space? >>
            (line_end.absent? >> any).repeat(1).as(:label_text)
        end

        # Line terminators for ER diagrams
        rule(:line_end) do
          semicolon.maybe >> space? >> (comment.maybe >> newline | eof)
        end
      end
    end
  end
end
