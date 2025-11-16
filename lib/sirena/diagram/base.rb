# frozen_string_literal: true

require 'lutaml/model'

module Sirena
  module Diagram
    # Abstract base class for all diagram models.
    #
    # This class provides common attributes and functionality shared across
    # all diagram types. Specific diagram types (Flowchart, Sequence, etc.)
    # inherit from this base and add their type-specific attributes.
    #
    # All diagram models use Lutaml::Model for serialization support.
    #
    # @example Define a custom diagram type
    #   class Flowchart < Diagram::Base
    #     attribute :nodes, :array
    #     attribute :edges, :array
    #   end
    #
    # @abstract Subclass and add diagram-specific attributes
    class Base < Lutaml::Model::Serializable
      # Unique identifier for the diagram
      attribute :id, :string

      # Optional title for the diagram
      attribute :title, :string

      # Direction or orientation of the diagram
      # (e.g., 'TB' for top-to-bottom, 'LR' for left-to-right)
      attribute :direction, :string

      # Optional theme or style configuration
      attribute :theme, :string

      # Validates that required diagram structure is present.
      #
      # This method should be overridden by subclasses to implement
      # diagram-specific validation logic.
      #
      # @return [Boolean] true if diagram is valid
      # @raise [NotImplementedError] if not implemented by subclass
      def valid?
        raise NotImplementedError,
              "#{self.class} must implement #valid?"
      end

      # Returns the diagram type identifier.
      #
      # This method should be overridden by subclasses to return their
      # specific diagram type.
      #
      # @return [Symbol] the diagram type identifier
      # @raise [NotImplementedError] if not implemented by subclass
      def diagram_type
        raise NotImplementedError,
              "#{self.class} must implement #diagram_type"
      end
    end
  end
end
