# frozen_string_literal: true

require_relative '../../diagram/er_diagram'

module Sirena
  module Parser
    module Transforms
      # Transform for converting Parslet parse tree to ER diagram model.
      #
      # Converts the parse tree output from Grammars::ErDiagram into a
      # fully-formed Diagram::ErDiagram object with entities, attributes,
      # and relationships.
      class ErDiagram
        # Cardinality symbol mappings
        CARDINALITY_SYMBOLS = {
          '||' => 'one',
          'o{' => 'zero_or_more',
          '|{' => 'one_or_more',
          '}o' => 'zero_or_one',
          '{o' => 'zero_or_more',
          '{|' => 'one_or_more',
          '}{' => 'one_or_more',
          '{}' => 'one_or_more'
        }.freeze

        # Transform parse tree into ER diagram.
        #
        # @param tree [Array, Hash] Parslet parse tree
        # @return [Diagram::ErDiagram] the ER diagram model
        def apply(tree)
          diagram = Diagram::ErDiagram.new

          # Tree is an array: [header, ...statements]
          if tree.is_a?(Array)
            tree.each do |item|
              next if item.is_a?(Hash) && item[:header] # Skip header
              process_statement(diagram, item) if item.is_a?(Hash)
            end
          elsif tree.is_a?(Hash) && tree[:statements]
            process_statements(diagram, tree[:statements])
          end

          diagram
        end

        private

        def process_statements(diagram, statements)
          Array(statements).each do |stmt|
            process_statement(diagram, stmt) if stmt.is_a?(Hash)
          end
        end

        def process_statement(diagram, stmt)
          return unless stmt.is_a?(Hash)

          if stmt[:entity_id] && stmt[:attributes]
            # Entity definition with attributes
            process_entity_definition(diagram, stmt)
          elsif stmt[:from_id] && stmt[:to_id] && stmt[:pattern]
            # Relationship
            process_relationship(diagram, stmt)
          elsif stmt[:entity_id]
            # Stand-alone entity declaration
            ensure_entity(diagram, stmt[:entity_id].to_s)
          end
        end

        def process_entity_definition(diagram, stmt)
          entity_id = stmt[:entity_id].to_s
          entity = find_or_create_entity(diagram, entity_id)

          # Process attributes
          if stmt[:attributes]
            attributes = Array(stmt[:attributes])
            attributes.each do |attr_data|
              next unless attr_data.is_a?(Hash)

              attribute = Diagram::ErAttribute.new.tap do |attr|
                attr.name = attr_data[:name].to_s
                attr.attribute_type = extract_text(attr_data[:type]) if attr_data[:type]
                attr.key_type = extract_key_type(attr_data[:key]) if attr_data[:key]
              end

              entity.attributes << attribute
            end
          end
        end

        def process_relationship(diagram, stmt)
          from_id = stmt[:from_id].to_s
          to_id = stmt[:to_id].to_s
          pattern = stmt[:pattern]

          # Ensure entities exist
          ensure_entity(diagram, from_id)
          ensure_entity(diagram, to_id)

          # Parse relationship pattern
          card_from = extract_text(pattern[:card_from])
          card_to = extract_text(pattern[:card_to])
          operator = extract_text(pattern[:operator])

          # Map cardinalities
          card_from_val = CARDINALITY_SYMBOLS[card_from]
          card_to_val = CARDINALITY_SYMBOLS[card_to]

          # Determine relationship type from operator
          rel_type = operator == '==' ? 'identifying' : 'non-identifying'

          # Extract label if present
          label = nil
          if stmt[:label] && stmt[:label][:label_text]
            label = extract_text(stmt[:label][:label_text]).strip
          end

          relationship = Diagram::ErRelationship.new.tap do |rel|
            rel.from_id = from_id
            rel.to_id = to_id
            rel.relationship_type = rel_type
            rel.cardinality_from = card_from_val
            rel.cardinality_to = card_to_val
            rel.label = label unless label.nil? || label.empty?
          end

          diagram.relationships << relationship
        end

        def find_or_create_entity(diagram, entity_id)
          existing = diagram.find_entity(entity_id)
          return existing if existing

          entity = Diagram::ErEntity.new.tap do |e|
            e.id = entity_id
            e.name = entity_id
          end
          diagram.entities << entity
          entity
        end

        def ensure_entity(diagram, entity_id)
          find_or_create_entity(diagram, entity_id)
        end

        def extract_text(value)
          case value
          when Hash
            if value[:string]
              value[:string].to_s
            elsif value[:key_type]
              value[:key_type].to_s
            else
              value.values.first.to_s
            end
          when String
            value
          else
            value.to_s
          end
        end

        def extract_key_type(value)
          text = extract_text(value)
          text if %w[PK FK UK].include?(text)
        end
      end
    end
  end
end