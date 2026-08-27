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
          (labelled_item | bare_item) >> metadata.maybe
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

        rule(:unquoted_value) do
          match['a-zA-Z0-9_\-'].repeat(1).as(:string)
        end

        root(:diagram)
      end
    end
  end
end