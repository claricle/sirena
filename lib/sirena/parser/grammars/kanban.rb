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
        # Named alternation branches rather than an inline `label.maybe`.
        # Both parse today's inputs identically, so this is about what comes
        # next: the deferred shape buckets add their branches here, and a
        # round-bracket branch has to sit BEFORE `bare_item`, which is the
        # most permissive of them. Ordering is the whole point of the rule,
        # so the branches are named and ordered rather than implied. This
        # matches how the other grammars in this directory are written -
        # see `mindmap.rb`'s `node` rule.
        rule(:item) do
          reserved_token.absent? >> (labelled_item | bare_item) >> metadata.maybe
        end

        # `kanban` is the diagram's own header token, and mermaid reserves it
        # as a node name: it refuses `kanban`, `Kanban` and `KANBAN`, bare or
        # carrying a bracket label, as a column or as a card. Only the whole
        # word is taken - `kanbanBoard` and `mykanban` are legal ids. No other
        # keyword is reserved: `graph`, `end`, `section`, `title`, `class`,
        # `classDef`, `click`, `style`, `subgraph`, `accTitle` and `accDescr`
        # all parse as ordinary nodes. Measured against mmdc 11.12.0 rather
        # than generalised from the one token.
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
        # unquoted scalar from a quoted one. Mermaid resolves an unquoted
        # value as YAML and drops the field when it lands on false, null or
        # zero, while any non-empty quoted string is kept.
        rule(:unquoted_value) do
          match['a-zA-Z0-9_\-'].repeat(1).as(:unquoted)
        end

        root(:diagram)
      end
    end
  end
end