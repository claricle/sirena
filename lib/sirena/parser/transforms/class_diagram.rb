# frozen_string_literal: true

require_relative '../../diagram/class_diagram'

module Sirena
  module Parser
    module Transforms
      # Transform for converting Parslet parse tree to Class diagram model.
      #
      # Converts the parse tree output from Grammars::ClassDiagram into a
      # fully-formed Diagram::ClassDiagram object with entities and
      # relationships.
      class ClassDiagram
        # Relationship type mappings from operators
        RELATIONSHIP_TYPES = {
          '<|--' => 'inheritance',
          '--|>' => 'inheritance',
          '*--' => 'composition',
          '--*' => 'composition',
          'o--' => 'aggregation',
          '--o' => 'aggregation',
          '-->' => 'association',
          '<--' => 'association',
          '--' => 'association',
          '..|>' => 'realization',
          '<|..' => 'realization',
          '..>' => 'dependency',
          '<..' => 'dependency',
          '..' => 'association'
        }.freeze

        # Operators where arrow points left (reverse direction)
        LEFT_POINTING = ['<|--', '<--', '<|..', '<..'].freeze

        # Visibility symbol mappings
        VISIBILITY_SYMBOLS = {
          '+' => 'public',
          '-' => 'private',
          '#' => 'protected',
          '~' => 'package'
        }.freeze

        # Transform parse tree into Class diagram.
        #
        # @param tree [Array, Hash] Parslet parse tree
        # @return [Diagram::ClassDiagram] the Class diagram model
        def apply(tree)
          @diagram = Diagram::ClassDiagram.new
          # Classes given an explicit label, so a later generic on the same id
          # does not append to it.
          @labelled_ids = []
          @current_namespace = nil

          # Tree is an array: [header, direction, ...statements]
          if tree.is_a?(Array)
            tree.each do |item|
              process_item(item) if item.is_a?(Hash)
            end
          elsif tree.is_a?(Hash)
            process_item(tree)
          end

          @diagram
        end

        private

        def process_item(item)
          return unless item.is_a?(Hash)

          # Process header to get direction
          if item[:direction] && item[:direction][:dir_value]
            @diagram.direction = extract_text(item[:direction][:dir_value])
          end

          # Process statements
          process_statement(item) unless item[:header] || item[:direction]
        end

        def process_statement(stmt)
          return unless stmt.is_a?(Hash)

          if stmt[:namespace_keyword]
            # Namespace block
            process_namespace(stmt)
          elsif stmt[:keyword] == 'class' && stmt[:class_id]
            # Class declaration
            process_class_declaration(stmt)
          elsif stmt[:stereotype] && stmt[:class_id] && !stmt[:keyword]
            # Standalone stereotype
            process_standalone_stereotype(stmt)
          elsif stmt[:class_id] && stmt[:member]
            # Colon member definition
            process_colon_member(stmt)
          elsif stmt[:from_id] && stmt[:to_id] && stmt[:operator]
            # Relationship
            process_relationship(stmt)
          elsif stmt[:link_keyword] || stmt[:callback_keyword]
            # Link or callback - ignore for now
            nil
          elsif stmt[:class_id] && !stmt[:keyword]
            # Standalone class
            ensure_entity_exists(extract_text(stmt[:class_id]))
          end
        end

        def process_namespace(stmt)
          namespace_name = extract_text(stmt[:namespace_name])
          old_namespace = @current_namespace
          @current_namespace = namespace_name

          # Process namespace body
          if stmt[:namespace_body]
            statements = Array(stmt[:namespace_body])
            statements.each do |s|
              process_statement(s) if s.is_a?(Hash)
            end
          end

          @current_namespace = old_namespace
        end

        def process_class_declaration(stmt)
          class_id = extract_text(stmt[:class_id])
          class_id = qualify_name(class_id)

          entity = find_or_create_entity(class_id)

          # `class C1[]` is an empty label and must fall back to the id, so an
          # empty string counts as absent here.
          label = extract_text(stmt[:text_label][:string]) if stmt[:text_label].is_a?(Hash)
          label = nil if label.nil? || label.empty?

          # Handle stereotype
          if stmt[:stereotype] && stmt[:stereotype][:stereotype_value]
            entity.stereotype = extract_text(stmt[:stereotype][:stereotype_value])
          end

          # Handle generic parameters.
          #
          # Appended to the name for display, but only when there is no
          # explicit label. mermaid renders `class Animal~T~["A label"]` as
          # "A label", not "A label~T~", so a label wins outright.
          # Skipped when a label is present on THIS declaration, and also when
          # an earlier declaration already labelled this class — otherwise
          # `class C1["Label"]` followed by `class C1~T~` produced `Label~T~`
          # where mmdc renders `Label`.
          if stmt[:generic] && stmt[:generic][:generic_type] && !label &&
             !@labelled_ids.include?(entity.id)
            generic_type = extract_text(stmt[:generic][:generic_type])
            entity.name = "#{entity.name}~#{generic_type}~"
          end

          # An explicit text label replaces the display name. The id is
          # untouched, which is what keeps relationships resolving — and the
          # assignment is unconditional on purpose, because
          # find_or_create_entity may have already set name to the id when a
          # relationship mentioned this class first.
          if label
            entity.name = label
            @labelled_ids << entity.id
          end

          # Handle class body
          process_class_body(entity, stmt[:body]) if stmt[:body]
        end

        def process_standalone_stereotype(stmt)
          class_id = extract_text(stmt[:class_id])
          class_id = qualify_name(class_id)

          entity = find_or_create_entity(class_id)

          if stmt[:stereotype][:stereotype_value]
            entity.stereotype = extract_text(stmt[:stereotype][:stereotype_value])
          end
        end

        def process_colon_member(stmt)
          class_id = extract_text(stmt[:class_id])
          class_id = qualify_name(class_id)

          entity = find_or_create_entity(class_id)

          # Parse visibility
          visibility = parse_visibility(stmt[:visibility])

          # Parse member
          member_data = stmt[:member]
          if member_data[:method_name]
            # It's a method
            add_method_to_entity(entity, member_data, visibility)
          else
            # It's an attribute
            add_attribute_to_entity(entity, member_data, visibility)
          end
        end

        def process_class_body(entity, body_data)
          return unless body_data.is_a?(Array)

          body_data.each do |member_item|
            next unless member_item.is_a?(Hash)
            next unless member_item[:member]

            visibility = parse_visibility(member_item[:visibility])
            member_data = member_item[:member]

            if member_data[:method_name]
              add_method_to_entity(entity, member_data, visibility)
            else
              add_attribute_to_entity(entity, member_data, visibility)
            end
          end
        end

        def add_method_to_entity(entity, method_data, visibility)
          method_name = extract_text(method_data[:method_name])
          parameters = method_data[:parameters] ? extract_text(method_data[:parameters]) : ''
          return_type = nil

          if method_data[:return_type] && method_data[:return_type][:type]
            return_type = extract_text(method_data[:return_type][:type])
          end

          method = Diagram::ClassMethod.new.tap do |m|
            m.name = method_name
            m.parameters = parameters
            m.return_type = return_type
            m.visibility = visibility
          end

          entity.class_methods << method
        end

        def add_attribute_to_entity(entity, attr_data, visibility)
          attr_name = extract_text(attr_data[:attr_name])
          attr_type = attr_data[:type] ? extract_text(attr_data[:type]) : nil

          attribute = Diagram::ClassAttribute.new.tap do |attr|
            attr.name = attr_name
            attr.type = attr_type
            attr.visibility = visibility
          end

          entity.attributes << attribute
        end

        def process_relationship(stmt)
          from_id = extract_text(stmt[:from_id])
          to_id = extract_text(stmt[:to_id])
          operator = extract_text(stmt[:operator][:arrow])

          # Qualify names if in namespace
          from_id = qualify_name(from_id)
          to_id = qualify_name(to_id)

          # Ensure both entities exist
          ensure_entity_exists(from_id)
          ensure_entity_exists(to_id)

          # Get relationship type
          relationship_type = RELATIONSHIP_TYPES[operator]
          relationship_type ||= 'association'

          # Parse cardinality
          source_card = nil
          target_card = nil

          if stmt[:source_card]
            source_card = extract_text(stmt[:source_card][:string])
          end

          if stmt[:target_card]
            target_card = extract_text(stmt[:target_card][:string])
          end

          # Parse label
          label = nil
          if stmt[:pipe_label] && stmt[:pipe_label][:label_text]
            label = extract_text(stmt[:pipe_label][:label_text])
            # Strip surrounding quotes if present
            label = label.gsub(/^["']|["']$/, '') if label
          elsif stmt[:colon_label] && stmt[:colon_label][:label_text]
            label = extract_text(stmt[:colon_label][:label_text]).strip
          end

          # Determine direction
          # For left-pointing arrows, reverse the relationship
          if LEFT_POINTING.include?(operator)
            actual_from = to_id
            actual_to = from_id
            # Swap cardinalities
            actual_source_card = target_card
            actual_target_card = source_card
          else
            actual_from = from_id
            actual_to = to_id
            actual_source_card = source_card
            actual_target_card = target_card
          end

          relationship = Diagram::ClassRelationship.new.tap do |rel|
            rel.from_id = actual_from
            rel.to_id = actual_to
            rel.relationship_type = relationship_type
            rel.label = label
            rel.source_cardinality = actual_source_card
            rel.target_cardinality = actual_target_card
          end

          @diagram.relationships << relationship
        end

        def find_or_create_entity(class_id)
          existing = @diagram.find_entity(class_id)
          return existing if existing

          entity = Diagram::ClassEntity.new.tap do |e|
            e.id = class_id
            e.name = class_id
          end
          @diagram.entities << entity
          entity
        end

        def ensure_entity_exists(class_id)
          find_or_create_entity(class_id)
        end

        def qualify_name(name)
          return name unless @current_namespace
          return name if name.include?('.')

          "#{@current_namespace}.#{name}"
        end

        def parse_visibility(vis_data)
          return 'public' unless vis_data

          symbol = extract_text(vis_data[:vis_symbol])
          VISIBILITY_SYMBOLS[symbol] || 'public'
        end

        def extract_text(value)
          case value
          when Hash
            if value[:string]
              value[:string].to_s
            elsif value[:arrow]
              value[:arrow].to_s
            elsif value[:stereotype_value]
              value[:stereotype_value].to_s
            elsif value[:dir_value]
              value[:dir_value].to_s
            elsif value[:label_text]
              value[:label_text].to_s
            elsif value[:vis_symbol]
              value[:vis_symbol].to_s
            elsif value[:type]
              value[:type].to_s
            elsif value[:attr_name]
              value[:attr_name].to_s
            elsif value[:method_name]
              value[:method_name].to_s
            else
              value.values.first.to_s
            end
          when String
            value
          else
            value.to_s
          end
        end
      end
    end
  end
end