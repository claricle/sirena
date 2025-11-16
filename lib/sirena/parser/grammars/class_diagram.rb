# frozen_string_literal: true

require_relative 'common'

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
          str('classDiagram').as(:header) >>
            ws? >>
            direction.maybe.as(:direction)
        end

        rule(:direction) do
          (str('TD') | str('TB') | str('LR') | str('RL') | str('BT')).as(:dir_value) >> ws?
        end

        rule(:statements) do
          (statement >> ws?).repeat(1)
        end

        rule(:statement) do
          namespace_block |
            class_declaration |
            standalone_stereotype |
            colon_member_definition |
            relationship |
            link_statement |
            callback_statement |
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
        rule(:class_declaration) do
          str('class').as(:keyword) >> space >>
            class_name.as(:class_id) >> space? >>
            stereotype.maybe.as(:stereotype) >> space? >>
            generic_params.maybe.as(:generic) >> space? >>
            class_body.maybe.as(:body) >>
            line_end
        end

        # Standalone stereotype: <<interface>> ClassName
        rule(:standalone_stereotype) do
          stereotype.as(:stereotype) >> space >>
            class_name.as(:class_id) >>
            line_end
        end

        # Colon member definition: ClassName : +member or ClassName : +method()
        rule(:colon_member_definition) do
          class_name.as(:class_id) >> space? >>
            colon >> space? >>
            visibility_modifier.maybe.as(:visibility) >>
            member_definition.as(:member) >>
            line_end
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

        # Standalone class (just an identifier)
        rule(:standalone_class) do
          class_name.as(:class_id) >> line_end
        end

        # Class name (identifier or dotted identifier)
        rule(:class_name) do
          (match['a-zA-Z_'] >> match['a-zA-Z0-9_.'].repeat)
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
          lbrace >> ws? >>
            class_members.maybe >>
            ws? >> rbrace
        end

        rule(:class_members) do
          (class_member >> ws?).repeat(1)
        end

        rule(:class_member) do
          visibility_modifier.maybe.as(:visibility) >>
            member_definition.as(:member)
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
          (
            match['a-zA-Z_'] >> match['a-zA-Z0-9_<>'].repeat >>
            (tilde >> (tilde.absent? >> any).repeat >> tilde).maybe
          )
        end

        # Visibility modifiers
        rule(:visibility_modifier) do
          (plus | minus | hash | tilde).as(:vis_symbol)
        end

        # Relationship: A relationship_operator B
        rule(:relationship) do
          class_name.as(:from_id) >> space? >>
            source_cardinality.maybe.as(:source_card) >> space? >>
            relationship_operator.as(:operator) >> space? >>
            pipe_label.maybe.as(:pipe_label) >> space? >>
            target_cardinality.maybe.as(:target_card) >> space? >>
            class_name.as(:to_id) >>
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

        # Relationship operators (8 types)
        rule(:relationship_operator) do
          inheritance_operator |
            composition_operator |
            aggregation_operator |
            realization_operator |
            dependency_operator |
            association_operator
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