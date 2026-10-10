# frozen_string_literal: true

module Sirena
  module Layout
    # Reads the namespace records an IR graph carries for a class diagram.
    module ClassDiagramNamespaces
      Namespace = Struct.new(:name, :class_ids, keyword_init: true)

      module_function

      # @param graph [IR::Graph] a class diagram graph
      # @return [Array<Namespace>] the namespaces in source order
      def call(graph)
        children = graph.nodes.group_by(&:parent_id)
        graph.nodes.select { |node| node.role == "namespace" }.map do |node|
          members = Array(children[node.id]).select { |n| n.role == "member" }
          Namespace.new(name: node.label, class_ids: members.map(&:label))
        end
      end
    end
  end
end
