# frozen_string_literal: true

require "lutaml/model"
require_relative "base"

module Sirena
  module Diagram
    # Architecture diagram model representing system architecture visualization
    class ArchitectureDiagram < Base
      # Group (boundary) in architecture diagram
      class Group < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :label, :string
        attribute :icon, :string
        attribute :parent_id, :string
      end

      # Service/component in architecture diagram
      class Service < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :label, :string
        attribute :icon, :string
        attribute :group_id, :string
      end

      # Edge (relationship) between services
      class Edge < Lutaml::Model::Serializable
        attribute :from_id, :string
        attribute :to_id, :string
        attribute :from_position, :string
        attribute :to_position, :string
        attribute :label, :string
      end

      attribute :title, :string
      attribute :acc_title, :string
      attribute :acc_descr, :string
      attribute :groups, Group, collection: true, default: -> { [] }
      attribute :services, Service, collection: true, default: -> { [] }
      attribute :edges, Edge, collection: true, default: -> { [] }

      # Returns the diagram type identifier.
      #
      # @return [Symbol] :architecture
      def diagram_type
        :architecture
      end

      # Architecture diagrams have no validation rules yet — nothing here
      # checks group/service/edge references. See TODO.foundation's corpus
      # burndown for real validation; this is deliberately trivial.
      #
      # @return [Boolean] true
      def valid?
        true
      end
    end
  end
end