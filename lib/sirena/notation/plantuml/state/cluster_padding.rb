# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module State
        # The room PlantUML (graphviz) keeps between a composite's border and
        # what it holds. It depends on the transitions at the border, not on
        # the composite: a transition that ends at the composite itself,
        # such as the one a start marker draws into it, leaves the room
        # small; a transition between a state inside and one outside makes it
        # larger; and both together make it larger still. Measured on
        # PlantUML 1.2026.6.
        class ClusterPadding
          # @!attribute left
          #   @return [Float] the room at the left of the children
          # @!attribute right
          #   @return [Float] the room at the right of the children
          # @!attribute bottom
          #   @return [Float] the room below the children
          # @!attribute title
          #   @return [Float] the room a title keeps beside its text
          Room = Data.define(:left, :right, :bottom, :title)

          # PlantUML keeps 12 at the left. The left stays 24: a composite
          # that narrow moves the layout of its siblings and the labels
          # reach no longer fits, which widens the canvas past the JAR's.
          BARE = Room.new(left: 24.0, right: 24.0, bottom: 13.0, title: 20.0)
          CROSSED = Room.new(left: 16.0, right: 16.0, bottom: 16.0,
                             title: 15.5)
          BOTH = Room.new(left: 24.0, right: 24.0, bottom: 24.0, title: 15.5)
          private_constant :BARE, :CROSSED, :BOTH

          # @param edges [Array<Hash>] every transition of the graph
          # @param parent [Hash{String=>String}] the container of each state
          def initialize(edges, parent)
            @edges = edges.map { |edge| ends_of(edge) }
            @parent = parent
          end

          # @param id [String] a composite's id
          # @return [Room]
          def room(id)
            return BARE unless crossing?(id)

            own?(id) ? BOTH : CROSSED
          end

          private

          def ends_of(edge)
            [edge[:sources].first, edge[:targets].first]
          end

          def own?(id)
            @edges.any? { |ends| ends.include?(id) }
          end

          def crossing?(id)
            @edges.any? do |from, to|
              inside?(from, id) != inside?(to, id) &&
                [from, to].none?(id)
            end
          end

          def inside?(state, id)
            state = @parent[state]
            state = @parent[state] until state.nil? || state == id
            !state.nil?
          end
        end
      end
    end
  end
end
