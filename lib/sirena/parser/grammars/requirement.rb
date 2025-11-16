# frozen_string_literal: true

require_relative 'common'

module Sirena
  module Parser
    module Grammars
      # Parslet grammar for Requirement diagrams.
      #
      # Handles requirement diagram syntax including requirements, elements,
      # relationships, styling, and class assignments.
      class Requirement < Common
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
          str('requirementDiagram').as(:header) >> ws?
        end

        rule(:statements) do
          (statement >> ws?).repeat(1)
        end

        rule(:statement) do
          requirement_statement |
            element_statement |
            relationship_statement |
            style_statement |
            class_definition_statement |
            class_assignment_statement
        end

        # Requirement: requirement [type] name { properties }
        # or: functionalRequirement name { properties }
        rule(:requirement_statement) do
          requirement_keyword.as(:req_type) >>
            space >>
            identifier.as(:req_name) >>
            (ws? >> class_shorthand.as(:req_classes)).maybe >>
            ws? >>
            lbrace >>
            ws? >>
            properties.maybe.as(:req_properties) >>
            ws? >>
            rbrace >>
            line_end
        end

        rule(:requirement_keyword) do
          str('functionalRequirement') |
            str('interfaceRequirement') |
            str('performanceRequirement') |
            str('physicalRequirement') |
            str('designConstraint') |
            str('requirement')
        end

        # Element: element name { properties }
        rule(:element_statement) do
          str('element').as(:elem_keyword) >>
            space >>
            identifier.as(:elem_name) >>
            (ws? >> class_shorthand.as(:elem_classes)).maybe >>
            ws? >>
            lbrace >>
            ws? >>
            properties.maybe.as(:elem_properties) >>
            ws? >>
            rbrace >>
            line_end
        end

        # Properties: key: value pairs
        rule(:properties) do
          (property >> ws?).repeat(1)
        end

        rule(:property) do
          property_key.as(:key) >>
            ws? >>
            colon >>
            ws? >>
            property_value.as(:value) >>
            line_end
        end

        rule(:property_key) do
          (str('id') | str('text') | str('risk') | str('verifymethod') |
           str('type') | str('docref')).as(:prop_key)
        end

        rule(:property_value) do
          (line_end.absent? >> any).repeat(1)
        end

        # Relationship: source - type -> target
        rule(:relationship_statement) do
          identifier.as(:rel_source) >>
            ws? >>
            str('-') >>
            ws? >>
            relationship_type.as(:rel_type) >>
            ws? >>
            str('->') >>
            ws? >>
            identifier.as(:rel_target) >>
            line_end
        end

        rule(:relationship_type) do
          (str('contains') | str('copies') | str('derives') |
           str('satisfies') | str('verifies') | str('refines') |
           str('traces')).as(:type)
        end

        # Style: style target1 [target2 ...] fill:#f9f,stroke:#333
        rule(:style_statement) do
          str('style').as(:style_keyword) >> space >>
            style_targets.as(:style_targets) >> space >>
            style_properties.as(:style_props) >>
            line_end
        end

        rule(:style_targets) do
          identifier >> (comma >> ws? >> identifier).repeat
        end

        rule(:style_properties) do
          style_property >> (comma >> style_property).repeat
        end

        rule(:style_property) do
          (line_end.absent? >> comma.absent? >> any).repeat(1)
        end

        # Class definition: classDef className fill:#f9f,stroke:#333
        rule(:class_definition_statement) do
          str('classDef').as(:classdef_keyword) >> space >>
            identifier.as(:class_name) >>
            (space >> class_property).repeat(1).as(:class_props) >>
            line_end
        end

        rule(:class_property) do
          (line_end.absent? >> comma.absent? >> any).repeat(1)
        end

        # Class assignment: class target1,target2 className1,className2
        rule(:class_assignment_statement) do
          str('class').as(:class_keyword) >> space >>
            class_assign_targets.as(:class_targets) >> space >>
            class_assign_names.as(:class_names) >>
            line_end
        end

        rule(:class_assign_targets) do
          identifier >> (comma >> identifier).repeat
        end

        rule(:class_assign_names) do
          identifier >> (comma >> identifier).repeat
        end

        # Class shorthand: :::className or :::class1,class2
        rule(:class_shorthand) do
          str(':::') >> class_shorthand_names
        end

        rule(:class_shorthand_names) do
          identifier >> (comma >> identifier).repeat
        end

        # Line terminator
        rule(:line_end) do
          space? >> (comment.maybe >> newline | eof)
        end
      end
    end
  end
end