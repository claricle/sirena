# frozen_string_literal: true

require_relative "../../../ir"

module Sirena
  module Notation
    module PlantUML
      module IRAdapter
        # Collects the IR nodes and edges an encoder emits and numbers them.
        # Ids are synthetic ("n0", "e0") so no source spelling can collide.
        class Sink
          attr_reader :nodes, :edges

          def initialize
            @nodes = []
            @edges = []
          end

          # @return [IR::Node] the node, already appended
          def node(role, label = nil, parent: nil)
            item = IR::Node.new(id: "n#{@nodes.size}", role: role,
                                label: label, parent_id: parent&.id)
            @nodes << item
            item
          end

          # Appends a child of `parent` carrying `value`, unless it is nil.
          def detail(parent, role, value)
            return if value.nil?

            node(role, value.to_s, parent: parent)
          end

          def details(parent, role, values)
            values.each { |value| detail(parent, role, value) }
          end

          def edge(role, source, target, **attributes)
            item = IR::Edge.new(id: "e#{@edges.size}", role: role,
                                source_id: source.id, target_id: target.id,
                                **attributes)
            @edges << item
            item
          end
        end
      end
    end
  end
end
