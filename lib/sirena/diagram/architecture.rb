# frozen_string_literal: true

require "lutaml/model"
require_relative "base"
require_relative "containment"

module Sirena
  module Diagram
    # Architecture diagram model representing system architecture visualization
    class Architecture < Base
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

      # Junction (routing point) in architecture diagram. Carries no icon
      # or label - it exists only so edges can bend between services.
      class Junction < Lutaml::Model::Serializable
        attribute :id, :string
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
      attribute :junctions, Junction, collection: true, default: -> { [] }
      attribute :edges, Edge, collection: true, default: -> { [] }

      # Returns the diagram type identifier.
      #
      # @return [Symbol] :architecture
      def diagram_type
        :architecture
      end

      # A group cannot be its own ancestor, and every group_id a service,
      # junction, or another group's parent_id names must belong to a
      # declared group. Neither the grammar nor the parser refuses either
      # shape. Left unchecked, a parent_id cycle poisons
      # Architecture's bounding-box arithmetic with
      # Infinity/-Infinity that later NaNs a comparison, and an undeclared
      # group_id is silently dropped from the render along with whatever
      # was placed in it — this stops both at the door instead.
      #
      # @return [Boolean] true if the diagram is valid
      def valid?
        return false if group_parent_cycle?
        return false unless group_references_resolve?

        true
      end

      private

      # Mirrors Flowchart#parent_cycle? — a group is its own ancestor.
      #
      # @return [Boolean] true when some group is its own ancestor
      def group_parent_cycle?
        graph = groups.each_with_object({}) do |group, acc|
          next if group.parent_id.nil?

          acc[group.id] = acc.fetch(group.id, []) | [group.parent_id]
        end

        !Containment.looping_pair(graph).nil?
      end

      # @return [Boolean] true when every parent_id and group_id names a
      #   group actually declared in the diagram
      def group_references_resolve?
        known = groups.map(&:id)

        groups.all? { |group| group.parent_id.nil? || known.include?(group.parent_id) } &&
          services.all? { |service| service.group_id.nil? || known.include?(service.group_id) } &&
          junctions.all? { |junction| junction.group_id.nil? || known.include?(junction.group_id) }
      end
    end
  end
end