# frozen_string_literal: true

require 'lutaml/model'
require_relative 'base'

module Sirena
  module Diagram
    # Represents a C4 element (Person, System, Container, Component).
    #
    # Elements are the nodes in C4 diagrams representing various architectural
    # entities like people, systems, containers, and components.
    class C4Element < Lutaml::Model::Serializable
      # Unique identifier for the element
      attribute :id, :string

      # Display label
      attribute :label, :string

      # Element type: Person, Person_Ext, System, System_Ext, SystemDb,
      # SystemDb_Ext, SystemQueue, SystemQueue_Ext, Container, ContainerDb,
      # ContainerQueue, Component
      attribute :element_type, :string

      # Description text
      attribute :description, :string

      # Technology stack (for Containers and Components)
      attribute :technology, :string

      # Sprite icon name
      attribute :sprite, :string

      # Link URL
      attribute :link, :string

      # Tags (comma-separated)
      attribute :tags, :string

      # Whether element is external (_Ext suffix)
      attribute :external, :boolean, default: -> { false }

      # Parent boundary ID (if nested)
      attribute :boundary_id, :string

      # Validates the element has required attributes.
      #
      # @return [Boolean] true if element is valid
      def valid?
        !id.nil? && !id.empty? &&
          !label.nil? && !label.empty? &&
          !element_type.nil?
      end

      # Returns base type without _Ext suffix
      #
      # @return [String] base element type
      def base_type
        element_type&.gsub(/_Ext$/, '') || element_type
      end

      # Check if element is a person
      #
      # @return [Boolean] true if person
      def person?
        base_type == 'Person'
      end

      # Check if element is a system
      #
      # @return [Boolean] true if system
      def system?
        %w[System SystemDb SystemQueue].include?(base_type)
      end

      # Check if element is a container
      #
      # @return [Boolean] true if container
      def container?
        %w[Container ContainerDb ContainerQueue].include?(base_type)
      end

      # Check if element is a component
      #
      # @return [Boolean] true if component
      def component?
        base_type == 'Component'
      end
    end

    # Represents a C4 relationship between elements.
    #
    # Relationships show interactions or dependencies between architectural
    # elements.
    class C4Relationship < Lutaml::Model::Serializable
      # Source element identifier
      attribute :from_id, :string

      # Target element identifier
      attribute :to_id, :string

      # Relationship label
      attribute :label, :string

      # Technology used in relationship
      attribute :technology, :string

      # Relationship type: Rel, BiRel
      attribute :rel_type, :string

      # Initialize with default type
      def initialize(*args)
        super
        self.rel_type ||= 'Rel'
      end

      # Validates the relationship has required attributes.
      #
      # @return [Boolean] true if relationship is valid
      def valid?
        !from_id.nil? && !from_id.empty? &&
          !to_id.nil? && !to_id.empty?
      end

      # Check if bidirectional relationship
      #
      # @return [Boolean] true if bidirectional
      def bidirectional?
        rel_type == 'BiRel'
      end
    end

    # Represents a C4 boundary grouping.
    #
    # Boundaries group related elements together, representing enterprise
    # boundaries, system boundaries, or custom boundaries.
    class C4Boundary < Lutaml::Model::Serializable
      # Unique identifier for the boundary
      attribute :id, :string

      # Display label
      attribute :label, :string

      # Boundary type: Enterprise_Boundary, System_Boundary, Boundary
      attribute :boundary_type, :string

      # Additional type parameter (for generic Boundary)
      attribute :type_param, :string

      # Link URL
      attribute :link, :string

      # Tags (comma-separated)
      attribute :tags, :string

      # Nested elements (element IDs)
      attribute :element_ids, :string, collection: true, default: -> { [] }

      # Nested boundaries (boundary IDs)
      attribute :boundary_ids, :string, collection: true, default: -> { [] }

      # Parent boundary ID (if nested)
      attribute :parent_id, :string

      # Initialize with default type
      def initialize(*args)
        super
        self.boundary_type ||= 'Boundary'
      end

      # Validates the boundary has required attributes.
      #
      # @return [Boolean] true if boundary is valid
      def valid?
        !id.nil? && !id.empty? &&
          !label.nil? && !label.empty?
      end

      # Check if enterprise boundary
      #
      # @return [Boolean] true if enterprise boundary
      def enterprise?
        boundary_type == 'Enterprise_Boundary'
      end

      # Check if system boundary
      #
      # @return [Boolean] true if system boundary
      def system?
        boundary_type == 'System_Boundary'
      end
    end

    # C4 diagram model.
    #
    # Represents a complete C4 diagram showing software architecture at
    # different levels of abstraction: Context, Container, Component, or Code.
    #
    # @example Creating a C4 Context diagram
    #   c4 = C4.new(level: 'Context')
    #   c4.title = 'System Context diagram'
    #   c4.elements << C4Element.new(
    #     id: 'customer',
    #     label: 'Customer',
    #     element_type: 'Person',
    #     description: 'A user of the system'
    #   )
    #   c4.elements << C4Element.new(
    #     id: 'system',
    #     label: 'Banking System',
    #     element_type: 'System',
    #     description: 'Main banking application'
    #   )
    #   c4.relationships << C4Relationship.new(
    #     from_id: 'customer',
    #     to_id: 'system',
    #     label: 'Uses'
    #   )
    class C4 < Base
      # C4 level: Context, Container, Component, Dynamic, Deployment
      attribute :level, :string

      # Diagram title
      attribute :title, :string

      # Collection of elements
      attribute :elements, C4Element, collection: true, default: -> { [] }

      # Collection of relationships
      attribute :relationships, C4Relationship, collection: true,
                                                 default: -> { [] }

      # Collection of boundaries
      attribute :boundaries, C4Boundary, collection: true, default: -> { [] }

      # Layout configuration
      attribute :layout_config, :string

      # Initialize with default level
      def initialize(*args)
        super
        self.level ||= 'Context'
      end

      # Returns the diagram type identifier.
      #
      # @return [Symbol] :c4
      def diagram_type
        :c4
      end

      # Validates the C4 diagram structure.
      #
      # A C4 diagram is valid if:
      # - It has a valid level
      # - All elements are valid
      # - All relationships are valid
      # - All boundaries are valid
      # - All relationship references point to existing elements
      #
      # @return [Boolean] true if C4 diagram is valid
      def valid?
        return false unless %w[Context Container Component Dynamic
                                Deployment].include?(level)
        return false unless elements.nil? || elements.all?(&:valid?)
        return false unless relationships.nil? ||
                            relationships.all?(&:valid?)
        return false unless boundaries.nil? || boundaries.all?(&:valid?)

        # Validate relationship references
        element_ids = elements.map(&:id)
        relationships&.each do |rel|
          return false unless element_ids.include?(rel.from_id)
          return false unless element_ids.include?(rel.to_id)
        end

        true
      end

      # Finds an element by its identifier.
      #
      # @param id [String] the element identifier to find
      # @return [C4Element, nil] the element or nil if not found
      def find_element(id)
        elements.find { |e| e.id == id }
      end

      # Finds a boundary by its identifier.
      #
      # @param id [String] the boundary identifier to find
      # @return [C4Boundary, nil] the boundary or nil if not found
      def find_boundary(id)
        boundaries.find { |b| b.id == id }
      end

      # Finds relationships from a specific element.
      #
      # @param element_id [String] the source element identifier
      # @return [Array<C4Relationship>] relationships from the element
      def relationships_from(element_id)
        relationships.select { |r| r.from_id == element_id }
      end

      # Finds relationships to a specific element.
      #
      # @param element_id [String] the target element identifier
      # @return [Array<C4Relationship>] relationships to the element
      def relationships_to(element_id)
        relationships.select { |r| r.to_id == element_id }
      end

      # Finds elements within a boundary.
      #
      # @param boundary_id [String] the boundary identifier
      # @return [Array<C4Element>] elements in the boundary
      def elements_in_boundary(boundary_id)
        elements.select { |e| e.boundary_id == boundary_id }
      end

      # Finds child boundaries within a parent boundary.
      #
      # @param boundary_id [String] the parent boundary identifier
      # @return [Array<C4Boundary>] child boundaries
      def boundaries_in_boundary(boundary_id)
        boundaries.select { |b| b.parent_id == boundary_id }
      end
    end
  end
end