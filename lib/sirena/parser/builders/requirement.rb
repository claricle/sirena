# frozen_string_literal: true

require "parslet"
require_relative "../../diagram/requirement"

module Sirena
  module Parser
    module Builders
      # Converts requirement diagram parse trees into diagram models.
      #
      # Handles transformation of requirements, elements, relationships,
      # styling directives, and class definitions from Parslet parse trees
      # into Requirement objects.
      class Requirement < Parslet::Transform
        JS_WHITESPACE_AT_EDGE = Regexp.new(
          '\A[\t\v\f\r\n\u0020\u00A0\u1680\u2000-\u200A' \
          '\u2028\u2029\u202F\u205F\u3000\uFEFF]+|' \
          '[\t\v\f\r\n\u0020\u00A0\u1680\u2000-\u200A' \
          '\u2028\u2029\u202F\u205F\u3000\uFEFF]+\z',
        )
        private_constant :JS_WHITESPACE_AT_EDGE

        # Requirement type mapping (for shorthand to full type)
        REQUIREMENT_TYPE_MAP = {
          "functionalRequirement" => "functionalRequirement",
          "interfaceRequirement" => "interfaceRequirement",
          "performanceRequirement" => "performanceRequirement",
          "physicalRequirement" => "physicalRequirement",
          "designConstraint" => "designConstraint",
          "requirement" => "requirement",
        }.freeze

        STATEMENT_HANDLERS = {
          req_type: %i[add_requirement create_requirement],
          elem_keyword: %i[add_element create_element],
          relationship: %i[add_relationship create_relationship],
          style_keyword: %i[add_style create_style],
          classdef_keyword: %i[add_class create_class_definition],
          class_keyword: %i[add_class_assignment create_class_assignment],
          acc_title: %i[acc_title= create_accessibility_title],
          acc_descr: %i[acc_description= create_accessibility_description],
        }.freeze
        private_constant :STATEMENT_HANDLERS

        REQUIREMENT_PROPERTIES = {
          "id" => :id=,
          "text" => :text=,
          "risk" => :risk=,
          "verifymethod" => :verifymethod=,
        }.freeze
        private_constant :REQUIREMENT_PROPERTIES

        ELEMENT_PROPERTIES = {
          "type" => :type=,
          "docref" => :docref=,
        }.freeze
        private_constant :ELEMENT_PROPERTIES

        STYLE_PROPERTIES = {
          "fill:" => :fill=,
          "stroke:" => :stroke=,
          "stroke-width:" => :stroke_width=,
        }.freeze
        private_constant :STYLE_PROPERTIES

        # Process parsed diagram
        def apply(tree, diagram = nil)
          diagram ||= Diagram::Requirement.new

          # The tree is an array of statement hashes
          statements = tree.is_a?(Array) ? tree : [tree]

          # Filter out header
          statements = statements.reject { |s| s.is_a?(Hash) && s[:header] }

          process_statements(diagram, statements)

          diagram
        end

        def process_statements(diagram, statements)
          statements.grep(Hash).each do |statement|
            process_statement(diagram, statement)
          end
        end

        def process_statement(diagram, statement)
          kind = statement_kind(statement)
          return unless kind

          writer, builder = STATEMENT_HANDLERS.fetch(kind)
          diagram.public_send(writer, send(builder, statement))
        end

        def statement_kind(statement)
          STATEMENT_HANDLERS.keys.find do |kind|
            if kind == :relationship
              statement[:rel_source] && statement[:rel_target]
            else
              statement[kind]
            end
          end
        end

        def create_accessibility_title(statement)
          acc_value(statement.fetch(:acc_title))
        end

        def create_accessibility_description(statement)
          acc_value(statement.fetch(:acc_descr))
        end

        # A zero-length accDescr capture (e.g. "accDescr {}", the only
        # acc_title/acc_descr grammar rule that can legally capture nothing
        # -- see acc_descr_multi_line in grammars/requirement.rb) comes back
        # from Parslet as an empty Array, not an empty String -- `[].to_s`
        # is the literal text "[]", not "". Route every acc_title/acc_descr
        # value through this so an empty directive value becomes "",
        # matching Mermaid.
        def acc_value(captured)
          return "" if captured.is_a?(Array) && captured.empty?

          captured.to_s.gsub(JS_WHITESPACE_AT_EDGE, "")
        end

        def create_requirement(stmt)
          Diagram::RequirementNode.new.tap do |req|
            req.name = stmt[:req_name].to_s
            req.type = stmt[:req_type].to_s
            assign_properties(
              req, stmt[:req_properties], REQUIREMENT_PROPERTIES
            )
            assign_classes(req, stmt[:req_classes])
          end
        end

        def create_element(stmt)
          Diagram::RequirementElement.new.tap do |elem|
            elem.name = stmt[:elem_name].to_s
            assign_properties(elem, stmt[:elem_properties], ELEMENT_PROPERTIES)
            assign_classes(elem, stmt[:elem_classes])
          end
        end

        def create_relationship(stmt)
          Diagram::RequirementRelationship.new.tap do |rel|
            rel.source = stmt[:rel_source].to_s
            rel.target = stmt[:rel_target].to_s
            type = stmt.dig(:rel_type, :type)
            rel.type = type.to_s if type
          end
        end

        def create_style(stmt)
          Diagram::RequirementStyle.new.tap do |style|
            assign_list(style, stmt[:style_targets], :add_target)
            assign_style_properties(style, stmt[:style_props])
          end
        end

        def create_class_definition(stmt)
          Diagram::RequirementClass.new.tap do |klass|
            klass.name = stmt[:class_name].to_s
            assign_style_properties(klass, stmt[:class_props])
          end
        end

        def create_class_assignment(stmt)
          Diagram::RequirementClassAssignment.new.tap do |assignment|
            assign_list(assignment, stmt[:class_targets], :add_target)
            assign_list(assignment, stmt[:class_names], :add_class)
          end
        end

        def assign_properties(target, captures, writers)
          arrayify(captures).grep(Hash).each do |property|
            key = property.dig(:key, :prop_key).to_s
            writer = writers[key]
            value = property[:value]&.to_s&.strip
            target.public_send(writer, value) if writer
          end
        end

        def assign_classes(target, captures)
          extract_class_names(captures).each { |name| target.add_class(name) }
        end

        def assign_list(target, captures, writer)
          arrayify(captures).each do |capture|
            split_list(capture).each do |value|
              target.public_send(writer, value)
            end
          end
        end

        def assign_style_properties(target, captures)
          parts = arrayify(captures).flat_map { |capture| split_list(capture) }
          parts.each do |part|
            assign_style_property(target, part)
          end
        end

        def assign_style_property(target, property)
          prefix, writer = STYLE_PROPERTIES.find do |candidate, _method|
            property.start_with?(candidate)
          end
          return target.add_property(property) unless writer

          target.public_send(writer, property.delete_prefix(prefix).strip)
        end

        def arrayify(value)
          return [] unless value

          value.is_a?(Array) ? value : [value]
        end

        def split_list(value)
          value.to_s.split(",").map(&:strip).reject(&:empty?)
        end

        def extract_class_names(class_data)
          # Shorthand arrives as a Parslet::Slice (":::a,b"), not a String.
          Array(class_data)
            .flat_map { |item| split_list(item.to_s.delete_prefix(":::")) }
        end
      end
    end
  end
end
