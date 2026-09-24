# frozen_string_literal: true

require 'parslet'
require_relative '../../diagram/requirement'

module Sirena
  module Parser
    module Builders
      # Transform for converting requirement diagram parse trees to diagram models.
      #
      # Handles transformation of requirements, elements, relationships,
      # styling directives, and class definitions from Parslet parse trees
      # into Requirement objects.
      class Requirement < Parslet::Transform
        JS_WHITESPACE_AT_EDGE = /\A[\t\v\f\r\n\u0020\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF]+|[\t\v\f\r\n\u0020\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF]+\z/
        private_constant :JS_WHITESPACE_AT_EDGE

        # Requirement type mapping (for shorthand to full type)
        REQUIREMENT_TYPE_MAP = {
          'functionalRequirement' => 'functionalRequirement',
          'interfaceRequirement' => 'interfaceRequirement',
          'performanceRequirement' => 'performanceRequirement',
          'physicalRequirement' => 'physicalRequirement',
          'designConstraint' => 'designConstraint',
          'requirement' => 'requirement'
        }.freeze

        # Process parsed diagram
        def self.apply(tree, diagram = nil)
          diagram ||= Diagram::Requirement.new

          # The tree is an array of statement hashes
          statements = tree.is_a?(Array) ? tree : [tree]

          # Filter out header
          statements = statements.reject { |s| s.is_a?(Hash) && s[:header] }

          process_statements(diagram, statements)

          diagram
        end

        def self.process_statements(diagram, statements)
          statements.each do |stmt|
            next unless stmt.is_a?(Hash)

            if stmt[:req_type]
              # Requirement statement
              requirement = create_requirement(stmt)
              diagram.add_requirement(requirement)
            elsif stmt[:elem_keyword]
              # Element statement
              element = create_element(stmt)
              diagram.add_element(element)
            elsif stmt[:rel_source] && stmt[:rel_target]
              # Relationship statement
              relationship = create_relationship(stmt)
              diagram.add_relationship(relationship)
            elsif stmt[:style_keyword]
              # Style statement
              style = create_style(stmt)
              diagram.add_style(style)
            elsif stmt[:classdef_keyword]
              # Class definition
              klass = create_class_definition(stmt)
              diagram.add_class(klass)
            elsif stmt[:class_keyword]
              # Class assignment
              assignment = create_class_assignment(stmt)
              diagram.add_class_assignment(assignment)
            elsif stmt[:acc_title]
              diagram.acc_title = acc_value(stmt[:acc_title])
            elsif stmt[:acc_descr]
              diagram.acc_description = acc_value(stmt[:acc_descr])
            end
          end
        end

        # A zero-length accDescr capture (e.g. "accDescr {}", the only
        # acc_title/acc_descr grammar rule that can legally capture nothing
        # -- see acc_descr_multi_line in grammars/requirement.rb) comes back
        # from Parslet as an empty Array, not an empty String -- `[].to_s`
        # is the literal text "[]", not "". Route every acc_title/acc_descr
        # value through this so an empty directive value becomes "",
        # matching Mermaid.
        def self.acc_value(captured)
          return '' if captured.is_a?(Array) && captured.empty?

          captured.to_s.gsub(JS_WHITESPACE_AT_EDGE, '')
        end

        def self.create_requirement(stmt)
          Diagram::RequirementNode.new.tap do |req|
            req.name = stmt[:req_name].to_s
            req.type = stmt[:req_type].to_s

            # Process properties
            if stmt[:req_properties]
              props = stmt[:req_properties]
              props = [props] unless props.is_a?(Array)

              props.each do |prop|
                next unless prop.is_a?(Hash)

                key = prop[:key][:prop_key].to_s if prop[:key]
                value = prop[:value].to_s.strip if prop[:value]

                case key
                when 'id'
                  req.id = value
                when 'text'
                  req.text = value
                when 'risk'
                  req.risk = value
                when 'verifymethod'
                  req.verifymethod = value
                end
              end
            end

            # Process class shorthand
            if stmt[:req_classes]
              classes = extract_class_names(stmt[:req_classes])
              classes.each { |c| req.add_class(c) }
            end
          end
        end

        def self.create_element(stmt)
          Diagram::RequirementElement.new.tap do |elem|
            elem.name = stmt[:elem_name].to_s

            # Process properties
            if stmt[:elem_properties]
              props = stmt[:elem_properties]
              props = [props] unless props.is_a?(Array)

              props.each do |prop|
                next unless prop.is_a?(Hash)

                key = prop[:key][:prop_key].to_s if prop[:key]
                value = prop[:value].to_s.strip if prop[:value]

                case key
                when 'type'
                  elem.type = value
                when 'docref'
                  elem.docref = value
                end
              end
            end

            # Process class shorthand
            if stmt[:elem_classes]
              classes = extract_class_names(stmt[:elem_classes])
              classes.each { |c| elem.add_class(c) }
            end
          end
        end

        def self.create_relationship(stmt)
          Diagram::RequirementRelationship.new.tap do |rel|
            rel.source = stmt[:rel_source].to_s
            rel.target = stmt[:rel_target].to_s

            if stmt[:rel_type] && stmt[:rel_type][:type]
              rel.type = stmt[:rel_type][:type].to_s
            end
          end
        end

        def self.create_style(stmt)
          Diagram::RequirementStyle.new.tap do |style|
            # Process targets
            if stmt[:style_targets]
              targets = stmt[:style_targets]
              targets = [targets] unless targets.is_a?(Array)

              targets.each do |target|
                style.add_target(target.to_s)
              end
            end

            # Process properties
            if stmt[:style_props]
              props = stmt[:style_props]
              props = [props] unless props.is_a?(Array)

              props.each do |prop|
                prop_str = prop.to_s.strip
                # Split by comma if it contains multiple properties
                prop_parts = prop_str.split(',')

                prop_parts.each do |part|
                  part = part.strip
                  if part.start_with?('fill:')
                    style.fill = part.sub('fill:', '').strip
                  elsif part.start_with?('stroke:')
                    style.stroke = part.sub('stroke:', '').strip
                  elsif part.start_with?('stroke-width:')
                    style.stroke_width = part.sub('stroke-width:', '').strip
                  else
                    style.add_property(part) unless part.empty?
                  end
                end
              end
            end
          end
        end

        def self.create_class_definition(stmt)
          Diagram::RequirementClass.new.tap do |klass|
            klass.name = stmt[:class_name].to_s

            # Process properties
            if stmt[:class_props]
              props = stmt[:class_props]
              props = [props] unless props.is_a?(Array)

              props.each do |prop|
                prop_str = prop.to_s.strip
                # Split by comma if it contains multiple properties
                prop_parts = prop_str.split(',')

                prop_parts.each do |part|
                  part = part.strip
                  if part.start_with?('fill:')
                    klass.fill = part.sub('fill:', '').strip
                  elsif part.start_with?('stroke:')
                    klass.stroke = part.sub('stroke:', '').strip
                  elsif part.start_with?('stroke-width:')
                    klass.stroke_width = part.sub('stroke-width:', '').strip
                  else
                    klass.add_property(part) unless part.empty?
                  end
                end
              end
            end
          end
        end

        def self.create_class_assignment(stmt)
          Diagram::RequirementClassAssignment.new.tap do |assignment|
            # Process targets
            if stmt[:class_targets]
              targets = stmt[:class_targets]
              targets = [targets] unless targets.is_a?(Array)

              targets.each do |target|
                assignment.add_target(target.to_s)
              end
            end

            # Process class names
            if stmt[:class_names]
              names = stmt[:class_names]
              names = [names] unless names.is_a?(Array)

              names.each do |name|
                assignment.add_class(name.to_s)
              end
            end
          end
        end

        def self.extract_class_names(class_data)
          # Extract class names from shorthand syntax
          classes = []

          if class_data.is_a?(String)
            classes = class_data.split(',').map(&:strip)
          elsif class_data.is_a?(Array)
            class_data.each do |item|
              if item.is_a?(String)
                classes << item.strip
              elsif item.is_a?(Hash) && item[:string]
                classes << item[:string].to_s.strip
              else
                classes << item.to_s.strip
              end
            end
          elsif class_data.is_a?(Hash)
            # Could be a single identifier or complex structure
            classes << class_data.to_s.strip
          end

          classes
        end
      end
    end
  end
end
