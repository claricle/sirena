# frozen_string_literal: true

require_relative "capture_string"
require_relative "../../diagram/c4"

module Sirena
  module Parser
    module Builders
      # Transform for converting Parslet parse tree to C4 diagram model.
      #
      # Converts the parse tree output from Grammars::C4 into a
      # fully-formed Diagram::C4 object with elements, relationships, and
      # boundaries.
      class C4
        include CaptureString

        LEVELS = {
          "C4Context" => "Context",
          "C4Container" => "Container",
          "C4Component" => "Component",
          "C4Dynamic" => "Dynamic",
          "C4Deployment" => "Deployment",
        }.freeze
        private_constant :LEVELS

        STATEMENT_HANDLERS = {
          header: :ignore_statement,
          title: :process_title,
          config_params: :process_layout_config,
          boundary_type: :process_boundary,
          rel_type: :process_relationship,
          element_type: :process_element,
        }.freeze
        private_constant :STATEMENT_HANDLERS

        SCATTERED_STOP_KEYS = %i[
          element_type boundary_type rel_type title config_params header
        ].freeze
        private_constant :SCATTERED_STOP_KEYS

        BOUNDARY_FIELDS = {
          id: :id=,
          label: :label=,
          type: :type_param=,
          link: :link=,
          tags: :tags=,
        }.freeze
        private_constant :BOUNDARY_FIELDS

        ELEMENT_FIELDS = {
          id: :id=,
          label: :label=,
          description: :description=,
          technology: :technology=,
          sprite: :sprite=,
          link: :link=,
          tags: :tags=,
        }.freeze
        private_constant :ELEMENT_FIELDS

        RELATIONSHIP_FIELDS = {
          from: :from_id=,
          to: :to_id=,
          label: :label=,
          technology: :technology=,
        }.freeze
        private_constant :RELATIONSHIP_FIELDS

        def initialize
          @boundary_stack = []
          @current_boundary = nil
        end

        # Transform parse tree into C4 diagram.
        #
        # @param tree [Array, Hash] Parslet parse tree
        # @return [Diagram::C4] the C4 diagram model
        def apply(tree)
          diagram = Diagram::C4.new
          @boundary_stack = []
          @current_boundary = nil
          extract_level(diagram, tree)

          statements(tree).each { |item| process_statement(diagram, item) }

          diagram
        end

        private

        def statements(tree)
          return merge_scattered_attributes(tree) if tree.is_a?(Array)
          return [tree] if tree.is_a?(Hash)

          []
        end

        def merge_scattered_attributes(tree)
          result = []
          index = 0
          while index < tree.length
            item, index = merge_scattered_item(tree, index)
            result << item
          end
          result
        end

        def merge_scattered_item(tree, index)
          item = tree[index]
          return [item, index + 1] unless scattered_statement?(item)

          merge_following_attributes(tree, item, index + 1)
        end

        def scattered_statement?(item)
          item.is_a?(Hash) &&
            (item[:element_type] || item[:boundary_type]) && !item[:body]
        end

        def merge_following_attributes(tree, item, index)
          while mergeable_attribute?(tree[index])
            item = item.merge(tree[index])
            index += 1
          end
          [item, index]
        end

        def mergeable_attribute?(item)
          item.is_a?(Hash) && SCATTERED_STOP_KEYS.none? { |key| item[key] }
        end

        def extract_level(diagram, tree)
          header = find_header(tree)
          return unless header

          diagram.level = LEVELS.fetch(header[:header].to_s, "Context")
        end

        def find_header(tree)
          if tree.is_a?(Array)
            return tree.find { |item| item.is_a?(Hash) && item[:header] }
          end

          tree if tree.is_a?(Hash) && tree[:header]
        end

        def process_statement(diagram, stmt)
          return unless stmt.is_a?(Hash)

          kind = STATEMENT_HANDLERS.keys.find { |key| stmt[key] }
          send(STATEMENT_HANDLERS.fetch(kind), diagram, stmt) if kind
        end

        def ignore_statement(_diagram, _stmt); end

        def process_title(diagram, stmt)
          diagram.title = extract_text(stmt[:title])
        end

        def process_layout_config(diagram, stmt)
          params = stmt[:config_params]
          diagram.layout_config = config_parts(params).join(", ")
        end

        def config_parts(params)
          if params.is_a?(Array)
            return params.filter_map { |param| config_part(param, true) }
          end
          return [config_part(params, false)] if params.is_a?(Hash)

          []
        end

        def config_part(param, require_values)
          key = extract_text(param[:key]) if param[:key]
          value = extract_text(param[:value]) if param[:value]
          return if require_values && (!key || !value)

          "#{key}=#{value}"
        end

        def process_boundary(diagram, stmt)
          boundary = create_boundary(stmt)
          diagram.boundaries << boundary
          process_boundary_body(diagram, boundary, stmt[:body]) if stmt[:body]
          boundary.id
        end

        def create_boundary(stmt)
          Diagram::C4Boundary.new.tap do |boundary|
            boundary.boundary_type = type_name(stmt[:boundary_type])
            assign_fields(boundary, stmt, BOUNDARY_FIELDS)
            boundary.parent_id = @current_boundary if @current_boundary
          end
        end

        def process_boundary_body(diagram, boundary, body)
          old_boundary = @current_boundary
          @current_boundary = boundary.id
          nested_statements(body).each do |nested_item|
            process_nested_statement(diagram, boundary, nested_item)
          end
        ensure
          @current_boundary = old_boundary
        end

        def nested_statements(body)
          items = (body.is_a?(Array) ? body : [body]).flat_map do |item|
            item.is_a?(Hash) && item[:item] ? [item[:item]].flatten : []
          end
          merge_scattered_attributes(items)
        end

        def process_nested_statement(diagram, boundary, stmt)
          if stmt[:boundary_type]
            id = process_boundary(diagram, stmt)
            boundary.boundary_ids << id if id
          elsif stmt[:element_type]
            id = process_element(diagram, stmt)
            boundary.element_ids << id if id
          end
        end

        def process_element(diagram, stmt)
          element = create_element(stmt)
          element.boundary_id = @current_boundary if @current_boundary
          diagram.elements << element
          element.id
        end

        def create_element(stmt)
          Diagram::C4Element.new.tap do |element|
            element.element_type = type_name(stmt[:element_type])
            assign_fields(element, stmt, ELEMENT_FIELDS)
            element.external = element.element_type&.end_with?("_Ext") || false
          end
        end

        def process_relationship(diagram, stmt)
          relationship = Diagram::C4Relationship.new.tap do |item|
            item.rel_type = stmt[:rel_type].to_s
            assign_fields(item, stmt, RELATIONSHIP_FIELDS)
          end
          diagram.relationships << relationship
        end

        def assign_fields(target, stmt, fields)
          fields.each do |capture, writer|
            next unless stmt[capture]

            target.public_send(writer, extract_text(stmt[capture]))
          end
        end

        def type_name(value)
          return value.to_s unless value.is_a?(Hash) && value[:variable]

          extract_text(value[:variable][:var])
        end

        def extract_text(value)
          text = value.is_a?(Hash) ? extract_hash_text(value) : value.to_s
          text.strip
        end

        def extract_hash_text(value)
          return capture_string(value[:string]) if value[:string]
          return value[:var].to_s if value[:var]

          value.values.first.to_s
        end
      end
    end
  end
end
