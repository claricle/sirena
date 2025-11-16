# frozen_string_literal: true

require_relative 'common'

module Sirena
  module Parser
    module Grammars
      # Parslet grammar for ER diagrams.
      #
      # Handles Entity-Relationship diagram syntax including entities,
      # attributes, relationships with cardinality notation, and both
      # identifying and non-identifying relationships.
      class ErDiagram < Common
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
          entity_definition |
            relationship |
            entity_declaration
        end

        # Entity with attribute block
        rule(:entity_definition) do
          identifier.as(:entity_id) >> space? >>
            lbrace >> ws? >>
            attributes.maybe.as(:attributes) >>
            ws? >> rbrace >>
            line_end
        end

        # Relationship between entities
        rule(:relationship) do
          identifier.as(:from_id) >> space? >>
            relationship_pattern.as(:pattern) >> space? >>
            identifier.as(:to_id) >> space? >>
            relationship_label.maybe.as(:label) >>
            line_end
        end

        # Stand-alone entity (no body, no relationship)
        rule(:entity_declaration) do
          identifier.as(:entity_id) >> line_end
        end

        # Attributes within entity block
        rule(:attributes) do
          (attribute >> ws?).repeat(1)
        end

        rule(:attribute) do
          attribute_type.maybe.as(:type) >> space? >>
            identifier.as(:name) >> space? >>
            key_type.maybe.as(:key) >>
            (space? >> comment).maybe
        end

        rule(:attribute_type) do
          identifier
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
          str('||') | str('o{') | str('|{') | str('}o') |
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