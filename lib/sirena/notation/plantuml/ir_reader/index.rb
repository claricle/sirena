# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module IRReader
        # Looks up the nodes of one graph by role, parent and id.
        class Index
          # @param graph [IR::Graph]
          def initialize(graph)
            @graph = graph
            @children = graph.nodes.group_by(&:parent_id)
            @by_id = graph.nodes.to_h { |node| [node.id, node] }
          end

          def edges
            @graph.edges
          end

          def node(id)
            @by_id.fetch(id)
          end

          # @return [Array<IR::Node>] the nodes whose role is one of `roles`,
          #   in graph order
          def with_role(*roles)
            @graph.nodes.select { |node| roles.include?(node.role) }
          end

          # @return [Array<String>] the labels of `parent`'s `role` children
          def details(parent, role)
            children(parent, role).map(&:label)
          end

          # @return [String, nil] the label of the first such child
          def detail(parent, role)
            details(parent, role).first
          end

          def children(parent, *roles)
            @children.fetch(parent.id, []).select do |node|
              roles.include?(node.role)
            end
          end
        end
      end
    end
  end
end
