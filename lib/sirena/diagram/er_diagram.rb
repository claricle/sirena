# frozen_string_literal: true

require 'lutaml/model'
require_relative 'base'

module Sirena
  module Diagram
    # Represents an attribute in an ER diagram entity.
    #
    # An attribute has a name, optional type, and optional key type
    # (PK for primary key, FK for foreign key).
    class ErAttribute < Lutaml::Model::Serializable
      # Attribute name
      attribute :name, :string

      # Attribute type (e.g., 'string', 'int', 'date')
      attribute :attribute_type, :string

      # Key type: 'PK' (primary key), 'FK' (foreign key), or nil
      attribute :key_type, :string

      # Validates the attribute has required fields.
      #
      # @return [Boolean] true if attribute is valid
      def valid?
        !name.nil? && !name.empty?
      end

      # Checks if this is a primary key.
      #
      # @return [Boolean] true if key_type is 'PK'
      def primary_key?
        key_type == 'PK'
      end

      # Checks if this is a foreign key.
      #
      # @return [Boolean] true if key_type is 'FK'
      def foreign_key?
        key_type == 'FK'
      end
    end

    # Represents an entity in an ER diagram.
    #
    # An entity has an identifier, name, and collection of attributes.
    class ErEntity < Lutaml::Model::Serializable
      # Unique identifier for the entity
      attribute :id, :string

      # Display name for the entity
      attribute :name, :string

      # Collection of entity attributes
      attribute :attributes, ErAttribute, collection: true,
                                          default: -> { [] }

      # Validates the entity has required fields.
      #
      # @return [Boolean] true if entity is valid
      def valid?
        !id.nil? && !id.empty? && !name.nil? && !name.empty? &&
          attributes.all?(&:valid?)
      end
    end

    # Represents a relationship between entities in an ER diagram.
    #
    # A relationship connects two entities with cardinality on both ends
    # and a relationship type (identifying or non-identifying).
    class ErRelationship < Lutaml::Model::Serializable
      # Source entity identifier
      attribute :from_id, :string

      # Target entity identifier
      attribute :to_id, :string

      # Relationship type: 'identifying' or 'non-identifying'
      attribute :relationship_type, :string

      # Cardinality from source end (e.g., 'one', 'zero_or_more',
      # 'zero_or_one', 'one_or_more')
      attribute :cardinality_from, :string

      # Cardinality at target end (e.g., 'one', 'zero_or_more',
      # 'zero_or_one', 'one_or_more')
      attribute :cardinality_to, :string

      # Optional relationship label
      attribute :label, :string

      # Initialize with default relationship type
      def initialize(*args)
        super
        self.relationship_type ||= 'non-identifying'
      end

      # Validates the relationship has required fields.
      #
      # @return [Boolean] true if relationship is valid
      def valid?
        !from_id.nil? && !from_id.empty? &&
          !to_id.nil? && !to_id.empty? &&
          !relationship_type.nil? && !relationship_type.empty? &&
          !cardinality_from.nil? && !cardinality_from.empty? &&
          !cardinality_to.nil? && !cardinality_to.empty?
      end

      # Checks if this is an identifying relationship.
      #
      # @return [Boolean] true if identifying type
      def identifying?
        relationship_type == 'identifying'
      end

      # Checks if this is a non-identifying relationship.
      #
      # @return [Boolean] true if non-identifying type
      def non_identifying?
        relationship_type == 'non-identifying'
      end
    end

    # ER diagram model.
    #
    # Represents a complete Entity-Relationship diagram with entities
    # and their relationships. ER diagrams show the data model structure
    # with entities, attributes, and relationships.
    #
    # @example Creating a simple ER diagram
    #   diagram = ErDiagram.new
    #   diagram.entities << ErEntity.new(
    #     id: 'CUSTOMER',
    #     name: 'CUSTOMER'
    #   ).tap do |entity|
    #     entity.attributes << ErAttribute.new(
    #       name: 'id',
    #       attribute_type: 'int',
    #       key_type: 'PK'
    #     )
    #     entity.attributes << ErAttribute.new(
    #       name: 'name',
    #       attribute_type: 'string'
    #     )
    #   end
    #   diagram.entities << ErEntity.new(
    #     id: 'ORDER',
    #     name: 'ORDER'
    #   )
    #   diagram.relationships << ErRelationship.new(
    #     from_id: 'CUSTOMER',
    #     to_id: 'ORDER',
    #     relationship_type: 'non-identifying',
    #     cardinality_from: 'one',
    #     cardinality_to: 'zero_or_more',
    #     label: 'places'
    #   )
    class ErDiagram < Base
      # Collection of entities in the diagram
      attribute :entities, ErEntity, collection: true,
                                     default: -> { [] }

      # Collection of relationships between entities
      attribute :relationships, ErRelationship, collection: true,
                                                default: -> { [] }

      # Returns the diagram type identifier.
      #
      # @return [Symbol] :er_diagram
      def diagram_type
        :er_diagram
      end

      # Validates the ER diagram structure.
      #
      # An ER diagram is valid if:
      # - It has at least one entity
      # - All entities are valid
      # - All relationships are valid
      # - All relationship references point to existing entities
      #
      # @return [Boolean] true if ER diagram is valid
      def valid?
        return false if entities.nil? || entities.empty?
        return false unless entities.all?(&:valid?)
        return false unless relationships.nil? ||
                            relationships.all?(&:valid?)

        # Validate relationship references
        entity_ids = entities.map(&:id)
        relationships&.each do |rel|
          return false unless entity_ids.include?(rel.from_id)
          return false unless entity_ids.include?(rel.to_id)
        end

        true
      end

      # Finds an entity by its identifier.
      #
      # @param id [String] the entity identifier to find
      # @return [ErEntity, nil] the entity or nil if not found
      def find_entity(id)
        entities.find { |e| e.id == id }
      end

      # Finds all relationships from a specific entity.
      #
      # @param entity_id [String] the source entity identifier
      # @return [Array<ErRelationship>] relationships from the entity
      def relationships_from(entity_id)
        relationships.select { |r| r.from_id == entity_id }
      end

      # Finds all relationships to a specific entity.
      #
      # @param entity_id [String] the target entity identifier
      # @return [Array<ErRelationship>] relationships to the entity
      def relationships_to(entity_id)
        relationships.select { |r| r.to_id == entity_id }
      end

      # Finds all identifying relationships.
      #
      # @return [Array<ErRelationship>] identifying relationships
      def identifying_relationships
        relationships.select(&:identifying?)
      end

      # Finds all non-identifying relationships.
      #
      # @return [Array<ErRelationship>] non-identifying relationships
      def non_identifying_relationships
        relationships.select(&:non_identifying?)
      end
    end
  end
end
