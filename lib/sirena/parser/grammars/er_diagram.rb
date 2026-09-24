# frozen_string_literal: true

require_relative 'common'

module Sirena
  module Parser
    module Grammars
      # Matches a whole variable-length run in ONE `Regexp` scan, consumed
      # in bounded `Source#consume` calls. Do not replace this with
      # `match[...].repeat`: that hard-codes `source.consume(1)` per char,
      # and folding the one-char slices back with `Slice#+` is O(n^2) to
      # scan a single long run. See the gate record for the measured
      # timings and the two real bugs a Codex review found in an earlier
      # version of this class, both guarded against below.
      class RunPattern < Parslet::Atoms::Base
        # Below this, `Source#consume(n)`'s own `/(.|$){n}/m` still
        # compiles; above it Ruby's regex engine raises `RegexpError: too
        # big number for repeat range`, so a run longer than this needs
        # more than one `#consume` call.
        MAX_CHUNK = 50_000
        private_constant :MAX_CHUNK

        def initialize(pattern)
          super()
          @re = Regexp.new(pattern, Regexp::MULTILINE)
        end

        def try(source, context, _consume_all)
          scanner = source.instance_variable_get(:@str)
          return context.err(self, source, "Failed to match #{@re.inspect}") unless scanner.match?(@re)

          # `scanner.matched.length` is a CHARACTER count. Do not use
          # `source.matches?(@re)` here instead: it reports BYTE length,
          # which over-consumes on any multibyte match.
          char_length = scanner.matched.length
          start_position = source.pos
          buffer = +''
          remaining = char_length
          while remaining.positive?
            chunk_size = [remaining, MAX_CHUNK].min
            buffer << source.consume(chunk_size).to_s
            remaining -= chunk_size
          end

          # The third argument (line cache) is required: without it,
          # `#line_and_column` on this slice raises `ArgumentError`.
          succ(Parslet::Slice.new(start_position, buffer, source.instance_variable_get(:@line_cache)))
        end
      end
      private_constant :RunPattern

      # Parslet grammar for ER diagrams.
      #
      # Handles Entity-Relationship diagram syntax including entities,
      # attributes, relationships with cardinality notation, and both
      # identifying and non-identifying relationships.
      class ErDiagram < Common
        # ECMA-262 LineTerminator: what a JS `.` refuses to cross. Kept
        # single-quoted so the `\u` escapes stay literal text for the
        # regex engine to interpret, not Ruby string escapes.
        JS_LINE_TERMINATOR_CHARS = '\n\r  '
        private_constant :JS_LINE_TERMINATOR_CHARS

        # ECMA-262 WhiteSpace + LineTerminator: what JS `\s` matches.
        JS_WHITESPACE_CHARS = '\t\v\f    - ' \
                               '    　﻿\n\r'
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
          str('erDiagram').as(:header) >> ws?
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
          identifier.as(:entity_id) >>
            (str(':::') >> class_name_list.as(:entity_classes)).maybe >>
            space? >>
            lbrace >> ws? >>
            attributes.maybe.as(:attributes) >>
            ws? >> rbrace >>
            line_end
        end

        # Relationship between entities
        #
        # The two ends capture under DIFFERENT names. Parslet merges a
        # statement's captures into one hash, so giving both ends
        # `:entity_classes` drops the from-end silently, warning only on
        # stderr. A7 in the parser spec is the guard.
        rule(:relationship) do
          identifier.as(:from_id) >>
            (str(':::') >> class_name_list.as(:from_classes)).maybe >>
            space? >>
            relationship_pattern.as(:pattern) >> space? >>
            identifier.as(:to_id) >>
            (str(':::') >> class_name_list.as(:to_classes)).maybe >>
            space? >>
            relationship_label.maybe.as(:label) >>
            line_end
        end

        # Stand-alone entity (no body, no relationship)
        rule(:entity_declaration) do
          identifier.as(:entity_id) >>
            (str(':::') >> class_name_list.as(:entity_classes)).maybe >>
            line_end
        end

        # Style class declaration: `classDef name[,name] <styles>`
        #
        # The style run ends at `line_end`, not at a newline, and `line_end`
        # opens with `semicolon.maybe` — so `classDef x fill:#f96;` captures
        # `fill:#f96` and mermaid's optional trailing `;` is not part of the
        # style text. A15 pins it.
        rule(:class_def_statement) do
          str('classDef') >> space.repeat(1) >>
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

        # Mermaid's ER `COMMENT` token accepts only double-quoted text with
        # NO embedded quote and NO backslash escape -- unlike the shared
        # `string`/`single_quoted_string` rules in `common.rb`, which
        # accept single quotes and `\"` escapes (measured against mermaid
        # 11.16.1: `'a note'` and `"a\"b"` are both rejected as attribute
        # notes; only a plain `"..."` with no inner `"` is accepted).
        rule(:note) do
          str('"') >> match('[^"]').repeat.as(:string) >> str('"')
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
        # `(?:[^~<lineterm>]*~)+`. Each iteration is forced forward by its
        # trailing `~`, so this is a single linear scan for the whole run,
        # not one attempt per candidate closing tilde.
        rule(:tilde_marked_run) do
          RunPattern.new("~(?:[^~#{JS_LINE_TERMINATOR_CHARS}]*~)+")
        end

        # `[^\s]` in mermaid's lexer is JS's `\s`, which is the full
        # ECMA-262 WhiteSpace + LineTerminator set -- not just space, tab
        # and `\n`. `JS_WHITESPACE_CHARS` is the same set already used for
        # this in `lib/sirena/parser/grammars/flowchart.rb`
        # (`LINE_SPACE_CHARS`, plus `\n`/`\r` since this rule's `[^\s]`
        # excludes those too, unlike flowchart's line-space-only class).
        rule(:tilde_prefix) do
          RunPattern.new("[^~#{JS_WHITESPACE_CHARS}]*")
        end

        rule(:tilde_suffix) do
          RunPattern.new("[^#{JS_WHITESPACE_CHARS}]*")
        end

        rule(:key_type) do
          (str('PK') | str('FK') | str('UK')).as(:key_type)
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
          str('||') | str('o{') | str('|{') | str('}o') | str('}|') |
            str('o|') | str('|o') |
            str('{o') | str('{|') | str('}{') | str('{}')
        end

        # Relationship operators (2 characters)
        rule(:operator) do
          str('==') | str('--') | str('..')
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