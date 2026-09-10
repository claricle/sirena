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
        # The two ends capture under DIFFERENT names (:from_classes,
        # :to_classes). Parslet merges a statement's captures into one
        # hash, so giving both ends the same key would drop the from-end
        # silently the moment both sides declared classes.
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
        # The style run ends at `line_end`, not at a bare newline —
        # `line_end` opens with `semicolon.maybe`, so `classDef x fill:#f96;`
        # captures `fill:#f96` and mermaid's optional trailing `;` is not
        # part of the style text.
        rule(:class_def_statement) do
          str('classDef') >> space.repeat(1) >>
            class_name_list.as(:classdef_names) >> space.repeat(1) >>
            (line_end.absent? >> any).repeat(1).as(:classdef_styles) >>
            line_end
        end

        # One or more comma-separated class names, using the shared
        # `identifier` rule.
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