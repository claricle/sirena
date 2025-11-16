# frozen_string_literal: true

require 'lutaml/model'
require_relative 'base'

module Sirena
  module Diagram
    # Represents a class attribute in a UML class diagram.
    #
    # An attribute has a name, type, and visibility modifier that
    # controls its access level.
    class ClassAttribute < Lutaml::Model::Serializable
      # Attribute name
      attribute :name, :string

      # Attribute type (e.g., 'string', 'int', 'List~String~')
      attribute :type, :string

      # Visibility: :public (+), :private (-), :protected (#),
      # :package (~)
      attribute :visibility, :string

      # Initialize with default visibility
      def initialize(*args)
        super
        self.visibility ||= 'public'
      end

      # Validates the attribute has required fields.
      #
      # @return [Boolean] true if attribute is valid
      def valid?
        !name.nil? && !name.empty?
      end

      # Returns the UML visibility symbol.
      #
      # @return [String] the visibility symbol (+, -, #, ~)
      def visibility_symbol
        case visibility
        when 'public' then '+'
        when 'private' then '-'
        when 'protected' then '#'
        when 'package' then '~'
        else '+'
        end
      end
    end

    # Represents a class method in a UML class diagram.
    #
    # A method has a name, optional parameters, optional return type,
    # and visibility modifier.
    class ClassMethod < Lutaml::Model::Serializable
      # Method name
      attribute :name, :string

      # Method parameters (e.g., 'x: int, y: int')
      attribute :parameters, :string

      # Return type (e.g., 'string', 'void')
      attribute :return_type, :string

      # Visibility: :public (+), :private (-), :protected (#),
      # :package (~)
      attribute :visibility, :string

      # Initialize with default visibility
      def initialize(*args)
        super
        self.visibility ||= 'public'
      end

      # Validates the method has required fields.
      #
      # @return [Boolean] true if method is valid
      def valid?
        !name.nil? && !name.empty?
      end

      # Returns the UML visibility symbol.
      #
      # @return [String] the visibility symbol (+, -, #, ~)
      def visibility_symbol
        case visibility
        when 'public' then '+'
        when 'private' then '-'
        when 'protected' then '#'
        when 'package' then '~'
        else '+'
        end
      end

      # Returns the full method signature.
      #
      # @return [String] method signature with parameters and return type
      def signature
        sig = name
        sig += "(#{parameters})" if parameters && !parameters.empty?
        sig += " #{return_type}" if return_type && !return_type.empty?
        sig
      end
    end

    # Represents a class/entity in a UML class diagram.
    #
    # A class entity has an identifier, name, optional stereotype,
    # collection of attributes, and collection of methods.
    class ClassEntity < Lutaml::Model::Serializable
      # Unique identifier for the class
      attribute :id, :string

      # Display name for the class
      attribute :name, :string

      # Optional stereotype (e.g., 'interface', 'abstract', 'enum')
      attribute :stereotype, :string

      # Collection of class attributes
      attribute :attributes, ClassAttribute, collection: true,
                                             default: -> { [] }

      # Collection of class methods
      attribute :class_methods, ClassMethod, collection: true,
                                             default: -> { [] }

      # Validates the class entity has required fields.
      #
      # @return [Boolean] true if class entity is valid
      def valid?
        !id.nil? && !id.empty? && !name.nil? && !name.empty? &&
          attributes.all?(&:valid?) && class_methods.all?(&:valid?)
      end

      # Checks if this is an interface.
      #
      # @return [Boolean] true if stereotype is 'interface'
      def interface?
        stereotype == 'interface'
      end

      # Checks if this is an abstract class.
      #
      # @return [Boolean] true if stereotype is 'abstract'
      def abstract?
        stereotype == 'abstract'
      end

      # Checks if this is an enum.
      #
      # @return [Boolean] true if stereotype is 'enum'
      def enum?
        stereotype == 'enum'
      end
    end

    # Represents a relationship between classes in a UML class diagram.
    #
    # A relationship connects two classes with a specific type
    # (inheritance, composition, aggregation, or association) and
    # optional label and cardinality.
    class ClassRelationship < Lutaml::Model::Serializable
      # Source class identifier
      attribute :from_id, :string

      # Target class identifier
      attribute :to_id, :string

      # Relationship type: :inheritance, :composition, :aggregation,
      # :association, :dependency, :realization
      attribute :relationship_type, :string

      # Optional relationship label
      attribute :label, :string

      # Optional cardinality for source end (e.g., '1', '0..1', '1..*')
      attribute :source_cardinality, :string

      # Optional cardinality for target end (e.g., '1', '0..1', '1..*')
      attribute :target_cardinality, :string

      # Initialize with default relationship type
      def initialize(*args)
        super
        self.relationship_type ||= 'association'
      end

      # Validates the relationship has required fields.
      #
      # @return [Boolean] true if relationship is valid
      def valid?
        !from_id.nil? && !from_id.empty? &&
          !to_id.nil? && !to_id.empty? &&
          !relationship_type.nil? && !relationship_type.empty?
      end

      # Checks if this is an inheritance relationship.
      #
      # @return [Boolean] true if inheritance type
      def inheritance?
        relationship_type == 'inheritance'
      end

      # Checks if this is a composition relationship.
      #
      # @return [Boolean] true if composition type
      def composition?
        relationship_type == 'composition'
      end

      # Checks if this is an aggregation relationship.
      #
      # @return [Boolean] true if aggregation type
      def aggregation?
        relationship_type == 'aggregation'
      end

      # Checks if this is an association relationship.
      #
      # @return [Boolean] true if association type
      def association?
        relationship_type == 'association'
      end

      # Checks if this is a dependency relationship.
      #
      # @return [Boolean] true if dependency type
      def dependency?
        relationship_type == 'dependency'
      end

      # Checks if this is a realization relationship.
      #
      # @return [Boolean] true if realization type
      def realization?
        relationship_type == 'realization'
      end
    end

    # Class diagram model.
    #
    # Represents a complete UML class diagram with classes and their
    # relationships. Class diagrams show the static structure of a
    # system with classes, attributes, methods, and relationships.
    #
    # @example Creating a simple class diagram
    #   diagram = ClassDiagram.new(direction: 'TB')
    #   diagram.entities << ClassEntity.new(
    #     id: 'Animal',
    #     name: 'Animal'
    #   ).tap do |entity|
    #     entity.attributes << ClassAttribute.new(
    #       name: 'age',
    #       type: 'int',
    #       visibility: 'protected'
    #     )
    #     entity.class_methods << ClassMethod.new(
    #       name: 'breathe',
    #       visibility: 'public'
    #     )
    #   end
    #   diagram.entities << ClassEntity.new(
    #     id: 'Dog',
    #     name: 'Dog'
    #   ).tap do |entity|
    #     entity.class_methods << ClassMethod.new(
    #       name: 'bark',
    #       visibility: 'public'
    #     )
    #   end
    #   diagram.relationships << ClassRelationship.new(
    #     from_id: 'Dog',
    #     to_id: 'Animal',
    #     relationship_type: 'inheritance'
    #   )
    class ClassDiagram < Base
      # Collection of class entities in the diagram
      attribute :entities, ClassEntity, collection: true,
                                        default: -> { [] }

      # Collection of relationships between entities
      attribute :relationships, ClassRelationship, collection: true,
                                                   default: -> { [] }

      # Returns the diagram type identifier.
      #
      # @return [Symbol] :class_diagram
      def diagram_type
        :class_diagram
      end

      # Validates the class diagram structure.
      #
      # A class diagram is valid if:
      # - It has at least one entity
      # - All entities are valid
      # - All relationships are valid
      # - All relationship references point to existing entities
      #
      # @return [Boolean] true if class diagram is valid
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
      # @return [ClassEntity, nil] the entity or nil if not found
      def find_entity(id)
        entities.find { |e| e.id == id }
      end

      # Finds all relationships from a specific entity.
      #
      # @param entity_id [String] the source entity identifier
      # @return [Array<ClassRelationship>] relationships from the entity
      def relationships_from(entity_id)
        relationships.select { |r| r.from_id == entity_id }
      end

      # Finds all relationships to a specific entity.
      #
      # @param entity_id [String] the target entity identifier
      # @return [Array<ClassRelationship>] relationships to the entity
      def relationships_to(entity_id)
        relationships.select { |r| r.to_id == entity_id }
      end

      # Finds all inheritance relationships.
      #
      # @return [Array<ClassRelationship>] inheritance relationships
      def inheritance_relationships
        relationships.select(&:inheritance?)
      end

      # Finds all composition relationships.
      #
      # @return [Array<ClassRelationship>] composition relationships
      def composition_relationships
        relationships.select(&:composition?)
      end

      # Finds all aggregation relationships.
      #
      # @return [Array<ClassRelationship>] aggregation relationships
      def aggregation_relationships
        relationships.select(&:aggregation?)
      end

      # Finds parent classes for a given entity.
      #
      # @param entity_id [String] the entity identifier
      # @return [Array<ClassEntity>] parent entities
      def parent_entities(entity_id)
        parent_ids = relationships
                     .select { |r| r.from_id == entity_id && r.inheritance? }
                     .map(&:to_id)
        entities.select { |e| parent_ids.include?(e.id) }
      end

      # Finds child classes for a given entity.
      #
      # @param entity_id [String] the entity identifier
      # @return [Array<ClassEntity>] child entities
      def child_entities(entity_id)
        child_ids = relationships
                    .select { |r| r.to_id == entity_id && r.inheritance? }
                    .map(&:from_id)
        entities.select { |e| child_ids.include?(e.id) }
      end
    end
  end
end
