# frozen_string_literal: true

require_relative "../diagram/class_namespace"

module Sirena
  module Parser
    # Collects the `namespace Name { ... }` blocks of a class diagram parse
    # tree, with the ids of the classes the builder created inside each.
    class ClassNamespaces
      ID_KEYS = %i[class_id from_id to_id].freeze

      # @param tree [Array<Hash>] the class diagram parse tree
      # @param diagram [Diagram::ClassDiagram] the built diagram
      # @return [Array<Diagram::ClassNamespace>] one per distinct name, in
      #   source order
      def self.collect(tree, diagram)
        new(diagram).collect(tree)
      end

      def initialize(diagram)
        @ids = diagram.entities.map(&:id)
      end

      def collect(tree)
        blocks = Array(tree).select do |item|
          item.is_a?(Hash) && item[:namespace_keyword]
        end
        grouped = blocks.group_by { |block| block[:namespace_name].to_s }
        claim_last(grouped.map { |name, group| namespace(name, group) })
      end

      private

      def namespace(name, blocks)
        ids = blocks.flat_map { |block| member_ids(block) }
        Diagram::ClassNamespace.new(name: name, class_ids: ids.uniq)
      end

      def member_ids(block)
        Array(block[:namespace_body]).flat_map do |statement|
          ID_KEYS.filter_map { |key| known(statement[key]) }
        end
      end

      def known(slice)
        return unless slice

        id = slice.to_s.delete("`")
        id if @ids.include?(id)
      end

      # mmdc gives a class one parent: the last namespace that lists it.
      def claim_last(namespaces)
        namespaces.reverse_each.with_object([]) do |item, claimed|
          item.class_ids -= claimed
          claimed.concat(item.class_ids)
        end
        namespaces
      end
    end
  end
end
