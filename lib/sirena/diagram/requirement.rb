# frozen_string_literal: true

require "lutaml/model"

module Sirena
  module Diagram
    # Represents a requirement in the diagram
    class Requirement < Lutaml::Model::Serializable
      attribute :name, :string
      attribute :type, :string, default: -> { "requirement" }
      attribute :id, :string
      attribute :text, :string
      attribute :risk, :string # Low, Medium, High
      attribute :verifymethod, :string # Analysis, Inspection, Test, Demonstration
      attribute :classes, :string, collection: true, default: -> { [] }

      def add_class(class_name)
        classes << class_name
      end
    end

    # Represents an element in the diagram
    class RequirementElement < Lutaml::Model::Serializable
      attribute :name, :string
      attribute :type, :string
      attribute :docref, :string
      attribute :classes, :string, collection: true, default: -> { [] }

      def add_class(class_name)
        classes << class_name
      end
    end

    # Represents a relationship between requirements/elements
    class RequirementRelationship < Lutaml::Model::Serializable
      attribute :source, :string
      attribute :target, :string
      attribute :type, :string # contains, copies, derives, satisfies, verifies, refines, traces

      VALID_TYPES = %w[
        contains
        copies
        derives
        satisfies
        verifies
        refines
        traces
      ].freeze

      def valid?
        VALID_TYPES.include?(type)
      end
    end

    # Represents styling for a requirement or element
    class RequirementStyle < Lutaml::Model::Serializable
      attribute :target_ids, :string, collection: true, default: -> { [] }
      attribute :fill, :string
      attribute :stroke, :string
      attribute :stroke_width, :string
      attribute :properties, :string, collection: true, default: -> { [] }

      def add_target(id)
        target_ids << id
      end

      def add_property(property)
        properties << property
      end
    end

    # Represents a CSS class definition
    class RequirementClass < Lutaml::Model::Serializable
      attribute :name, :string
      attribute :fill, :string
      attribute :stroke, :string
      attribute :stroke_width, :string
      attribute :properties, :string, collection: true, default: -> { [] }

      def add_property(property)
        properties << property
      end
    end

    # Represents a class assignment to requirements/elements
    class RequirementClassAssignment < Lutaml::Model::Serializable
      attribute :target_ids, :string, collection: true, default: -> { [] }
      attribute :class_names, :string, collection: true, default: -> { [] }

      def add_target(id)
        target_ids << id
      end

      def add_class(class_name)
        class_names << class_name
      end
    end

    # Represents a Mermaid requirement diagram
    class RequirementDiagram < Lutaml::Model::Serializable
      attribute :requirements, Requirement, collection: true, default: -> { [] }
      attribute :elements, RequirementElement, collection: true, default: -> { [] }
      attribute :relationships, RequirementRelationship, collection: true, default: -> { [] }
      attribute :styles, RequirementStyle, collection: true, default: -> { [] }
      attribute :classes, RequirementClass, collection: true, default: -> { [] }
      attribute :class_assignments, RequirementClassAssignment, collection: true, default: -> { [] }

      def add_requirement(requirement)
        requirements << requirement
      end

      def add_element(element)
        elements << element
      end

      def add_relationship(relationship)
        relationships << relationship
      end

      def add_style(style)
        styles << style
      end

      def add_class(klass)
        classes << klass
      end

      def add_class_assignment(assignment)
        class_assignments << assignment
      end
    end
  end
end