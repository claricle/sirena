# frozen_string_literal: true

require_relative 'common'

module Sirena
  module Parser
    module Grammars
      # Parslet grammar for C4 diagrams.
      #
      # Handles C4 diagram syntax including Context, Container, Component,
      # Dynamic, and Deployment diagrams with elements, relationships, and
      # boundaries.
      class C4 < Common
        root(:diagram)

        # Main diagram structure
        rule(:diagram) do
          ws? >>
            header >>
            ws? >>
            statements.maybe >>
            ws?
        end

        # C4 level headers
        rule(:header) do
          (
            str('C4Context') |
            str('C4Container') |
            str('C4Component') |
            str('C4Dynamic') |
            str('C4Deployment') |
            str('C4 diagram')
          ).as(:header) >>
          # Allow optional ${whitespace} or ${variable} or semicolon after header
          (
            (dollar >> lbrace >> identifier >> rbrace) |
            str(';')
          ).maybe >>
          ws?
        end

        rule(:statements) do
          (statement >> ws?).repeat(1)
        end

        rule(:statement) do
          title_statement |
            update_layout_config |
            boundary |
            relationship |
            element
        end

        # Title statement
        rule(:title_statement) do
          str('title') >> space.repeat(1) >>
            (line_end.absent? >> dollar.absent? >> any).repeat(1).as(:title) >>
            # Allow optional ${whitespace} or ${variable} at end
            (dollar >> lbrace >> identifier >> rbrace).maybe >>
            line_end
        end

        # UpdateLayoutConfig
        rule(:update_layout_config) do
          str('UpdateLayoutConfig') >> space? >> lparen >> space? >>
            config_params.as(:config_params) >>
            space? >> rparen >> line_end
        end

        rule(:config_params) do
          config_param >>
            (space? >> comma >> space? >> config_param).repeat
        end

        rule(:config_param) do
          (dollar >> identifier).as(:key) >> space? >> equals >> space? >>
            (quoted_string | number).as(:value)
        end

        # Boundaries (can contain elements and nested boundaries)
        rule(:boundary) do
          boundary_type.as(:boundary_type) >> space? >> lparen >> space? >>
            boundary_params >>
            space? >> rparen >> space? >> lbrace >>
            ws? >>
            boundary_body.maybe.as(:body) >>
            ws? >>
            rbrace >> line_end
        end

        rule(:boundary_type) do
          str('Enterprise_Boundary') |
            str('System_Boundary') |
            str('Boundary') |
            # Handle variable boundary types like ${macroName}
            (dollar >> lbrace >> identifier.as(:var) >> rbrace).as(:variable)
        end

        rule(:boundary_params) do
          (variable_or_identifier).as(:id) >>
            (space? >> comma >> space? >>
             param_value.as(:label)).maybe >>
            (space? >> comma >> space? >>
             param_value.as(:type)).maybe >>
            boundary_attributes.maybe
        end

        rule(:boundary_body) do
          (boundary | element).as(:item) >>
            (ws? >> (boundary | element).as(:item)).repeat
        end

        rule(:boundary_attributes) do
          (space? >> comma >> space? >> boundary_attribute).repeat(1)
        end

        rule(:boundary_attribute) do
          (dollar >> str('link') >> equals >> quoted_string).as(:link) |
            (dollar >> str('tags') >> equals >> quoted_string).as(:tags)
        end

        # Elements (Person, System, Container, Component, etc.)
        rule(:element) do
          element_type.as(:element_type) >> space? >> lparen >> space? >>
            element_params >>
            space? >> rparen >>
            # Allow optional ${whitespace} or ${variable} at end
            (dollar >> lbrace >> identifier >> rbrace).maybe >>
            line_end
        end

        rule(:element_type) do
          # Order matters: check longer patterns first
          str('Enterprise_Boundary') | str('System_Boundary') |
            str('Person_Ext') | str('Person') |
            str('SystemDb_Ext') | str('SystemDb') |
            str('SystemQueue_Ext') | str('SystemQueue') |
            str('System_Ext') | str('System') |
            str('ContainerDb') | str('ContainerQueue') | str('Container') |
            str('Component') |
            # Handle variable element types
            (dollar >> lbrace >> identifier.as(:var) >> rbrace).as(:variable)
        end

        rule(:element_params) do
          (variable_or_identifier).as(:id) >>
            (space? >> comma >> space? >>
             param_value.as(:label)).maybe >>
            (space? >> comma >> space? >>
             param_value.as(:description)).maybe >>
            (space? >> comma >> space? >>
             param_value.as(:technology)).maybe >>
            element_attributes.maybe
        end

        rule(:element_attributes) do
          (space? >> comma >> space? >> element_attribute).repeat(1)
        end

        rule(:element_attribute) do
          (dollar >> str('sprite') >> equals >> quoted_string).as(:sprite) |
            (dollar >> str('link') >> equals >> quoted_string).as(:link) |
            (dollar >> str('tags') >> equals >> quoted_string).as(:tags)
        end

        # Relationships
        rule(:relationship) do
          relationship_type.as(:rel_type) >> space? >> lparen >> space? >>
            relationship_params >>
            space? >> rparen >>
            # Allow optional ${whitespace} or ${variable} at end
            (dollar >> lbrace >> identifier >> rbrace).maybe >>
            line_end
        end

        rule(:relationship_type) do
          str('BiRel') | str('Rel')
        end

        rule(:relationship_params) do
          (variable_or_identifier).as(:from) >>
            space? >> comma >> space? >>
            (variable_or_identifier).as(:to) >>
            (space? >> comma >> space? >>
             param_value.as(:label)).maybe >>
            (space? >> comma >> space? >>
             param_value.as(:technology)).maybe
        end

        # Parameter value (can be quoted string, unquoted text, or variable)
        # But should not match attributes (things starting with $name=)
        rule(:param_value) do
          quoted_string |
            variable_or_identifier |
            unquoted_param
        end

        rule(:unquoted_param) do
          # Don't match if it starts with $identifier=
          (dollar >> match['a-zA-Z_']).absent? >>
            (comma.absent? >> rparen.absent? >> line_end.absent? >>
             any).repeat(1)
        end

        # Variable or identifier
        rule(:variable_or_identifier) do
          variable | identifier
        end

        rule(:variable) do
          dollar >> lbrace >> identifier.as(:var) >> rbrace
        end

        rule(:dollar) { str('$') }

        # Override string to capture content
        rule(:quoted_string) do
          str('"') >> (
            str('\\') >> any | str('"').absent? >> any
          ).repeat.as(:string) >> str('"')
        end
      end
    end
  end
end