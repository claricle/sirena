# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # One element of a use case, component or deployment diagram: an
        # actor, a use case, a component, an interface, a deployment node or
        # a container holding other nodes.
        class Node
          CONTAINER_KINDS = %i[package node database cloud rectangle folder
                               frame storage artifact card namespace
                               component].freeze

          attr_reader :id, :parent
          attr_accessor :kind, :lines, :stereotype, :color, :sections, :table,
                        :sprite
          attr_writer :container

          # @param parent [Node, nil] the container this node sits in
          def initialize(id:, kind:, lines: nil, parent: nil)
            @id = id
            @kind = kind
            @lines = lines || [id]
            @parent = parent
            @container = false
          end

          def container?
            @container
          end

          # @return [Array<Node>] the containers around this node, outermost
          #   first
          def ancestors
            return [] unless parent

            parent.ancestors + [parent]
          end
        end
      end
    end
  end
end
