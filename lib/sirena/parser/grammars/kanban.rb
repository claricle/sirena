# frozen_string_literal: true

require_relative "common"

module Sirena
  module Parser
    module Grammars
      # Parslet grammar for Kanban diagrams
      class Kanban < Common
        rule(:diagram) do
          space? >>
            header >>
            (content_line).repeat(0).as(:lines) >>
            space?
        end

        rule(:header) do
          str("kanban") >> (newline | eof)
        end

        rule(:content_line) do
          empty_line | item_line
        end

        rule(:empty_line) do
          space? >> newline
        end

        rule(:item_line) do
          str(' ').repeat.as(:indent) >>
            item >>
            (newline | eof)
        end

        # An item can be either a column or a card. The label is optional:
        # mermaid accepts a bare id, with or without trailing metadata.
        #
        # Named alternation branches rather than folding the bracket label
        # into one rule as a `.maybe`.
        # `bare_item` is the most permissive branch and must stay last, or a
        # later branch that also starts with an identifier would never be
        # reached. `shaped_item` and `labelled_item` both require a specific
        # delimiter (`(` or `[`) right after the id, so their relative order
        # does not matter - Parslet fails one and tries the next without
        # consuming input. `unlabelled_shaped_item` opens on `(`, something
        # an identifier can never start with, so it stays reachable
        # wherever it sits. Naming the branches keeps the order explicit
        # rather than implied, which is how the other grammars in this
        # directory are written - see `mindmap.rb`'s `node` rule.
        rule(:item) do
          reserved_token.absent? >>
            (labelled_item | shaped_item | unlabelled_shaped_item | bare_item) >>
            metadata.maybe
        end

        # `kanban` is the diagram's own header token, and mermaid reserves it
        # as a node name: it refuses `kanban`, `Kanban` and `KANBAN`, bare or
        # carrying a bracket label, as a column or as a card. Only the whole
        # word is taken - `kanbanBoard` and `mykanban` are legal ids. Measured
        # against mmdc 11.12.0.
        #
        # No other keyword is reserved. The tokens checked are listed once,
        # in the spec that pins them - see the 'reserves no other keyword'
        # example in spec/sirena/parser/kanban_spec.rb.
        rule(:reserved_token) do
          kanban_keyword >> match['a-zA-Z0-9_'].absent?
        end

        # Parslet's `str` is case-sensitive and it offers no case-insensitive
        # literal, so the keyword is spelled out character by character.
        rule(:kanban_keyword) do
          match['kK'] >> match['aA'] >> match['nN'] >>
            match['bB'] >> match['aA'] >> match['nN']
        end

        rule(:labelled_item) do
          identifier.as(:id) >>
            lbracket >>
            match('[^\]]').repeat(1).as(:text) >>
            rbracket
        end

        # Round shape with an id: id(text) - mermaid's rounded-node syntax,
        # the same shorthand flowchart's `shape_rounded` parses. Sirena's
        # kanban renderer always draws a rounded rect for every item
        # regardless of source syntax (see Renderer::Kanban#render_column
        # and #render_card), so the delimiter is parsed only to recover the
        # label - no separate shape field is modeled, matching how the
        # bracket label above works.
        rule(:shaped_item) do
          identifier.as(:id) >>
            lparen >>
            round_text >>
            rparen
        end

        # Round shape with no id: (text). Mermaid auto-assigns an id here;
        # BoardBuilder does too, deterministically - see
        # Transforms::Kanban::BoardBuilder#resolve_id.
        rule(:unlabelled_shaped_item) do
          lparen >>
            round_text >>
            rparen
        end

        # Text inside a round shape - id(text) or (text). A quoted body is
        # tried first so it can contain an unescaped `)`, mermaid's own
        # rule for `Todo (urgent)`, and the surrounding quotes are excluded
        # from the capture rather than kept as literal characters - mermaid
        # strips them too. Falls back to the plain, unquoted body when the
        # first character isn't a `"`. Mirrors `square_shape` in
        # mindmap.rb, the existing precedent for quoted content inside a
        # bracketed shape in this grammar family.
        #
        # The unquoted body excludes `(`, `)`, `]` and `}` - mermaid's own
        # lexer treats all four as node-shape delimiters even unquoted
        # mid-label, and rejects a body carrying one (measured against mmdc
        # 11.12.0). `[` and `{` are not delimiters to it there and stay
        # literal, so they are not excluded - both parse in mermaid.
        rule(:round_text) do
          (str('"') >> match('[^"]').repeat(1).as(:text) >> str('"')) |
            (str('"').absent? >> match('[^()\]}]').repeat(1).as(:text))
        end

        # Deliberately just an identifier. Mermaid also accepts a bare label
        # containing spaces, but widening this to free text would swallow
        # `root(Root)` and `:::hot` as literal labels, turning unsupported
        # constructs into silently wrong output instead of parse failures.
        # `identifier` also refuses a leading digit, so `1col` fails to parse
        # while `col1` and `_col` are accepted.
        rule(:bare_item) do
          identifier.as(:id)
        end

        # Metadata: @{ key: 'value', key2: 'value2' }
        rule(:metadata) do
          str("@") >>
            space? >>
            lbrace >>
            space? >>
            metadata_entries.maybe.as(:metadata) >>
            space? >>
            rbrace
        end

        rule(:metadata_entries) do
          metadata_entry >> (comma >> space? >> metadata_entry).repeat
        end

        rule(:metadata_entry) do
          metadata_key.as(:key) >>
            space? >>
            colon >>
            space? >>
            metadata_value.as(:value)
        end

        rule(:metadata_key) do
          match['a-zA-Z_'] >> match['a-zA-Z0-9_'].repeat
        end

        rule(:metadata_value) do
          quoted_string | single_quoted_string | unquoted_value
        end

        # Captured as :unquoted, not :string, so the transform can tell an
        # unquoted scalar from a quoted one. What it does with that
        # distinction is `dropped_by_mermaid?`'s responsibility, not this rule's.
        #
        # `.`, `+` and `~` are in the set because js-yaml reads them and
        # mermaid draws them: `0.0`, `+0`, `~` and `.nan` are values it
        # resolves falsy, and `1.5` and `+7` values it keeps. Without them
        # the whole line failed to parse. None of the three ends a value -
        # a comma or a closing brace does - so the rule stays unambiguous.
        rule(:unquoted_value) do
          match['a-zA-Z0-9_\-.+~'].repeat(1).as(:unquoted)
        end

        root(:diagram)
      end
    end
  end
end