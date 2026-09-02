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
        # Both parse today's inputs identically, so this is about ordering:
        # `bare_item` is the most permissive branch and must stay last, or a
        # later branch that also starts with an identifier would never be
        # reached. A branch keyed on something an identifier cannot start -
        # `:::hot`, say - stays reachable either way. Naming the branches
        # keeps that order explicit rather than implied, which is how the
        # other grammars in this directory are written - see `mindmap.rb`'s
        # `node` rule.
        rule(:item) do
          reserved_token.absent? >> (labelled_item | bare_item) >> metadata.maybe
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
        rule(:unquoted_value) do
          match['a-zA-Z0-9_\-'].repeat(1).as(:unquoted)
        end

        root(:diagram)
      end
    end
  end
end