# frozen_string_literal: true

require "lutaml/model"

module Sirena
  module Diagram
    # Architecture diagram model representing system architecture visualization
    class ArchitectureDiagram < Lutaml::Model::Serializable
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

      def type
        "architecture"
      end
    end
  end
end