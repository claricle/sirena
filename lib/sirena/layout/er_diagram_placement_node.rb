# frozen_string_literal: true

module Sirena
  module Layout
    # One box in the placement: an entity, or the stand-in for a point
    # (or label) along a relationship that spans several ranks.
    class ErDiagramPlacementNode
      attr_reader :id, :width, :height

      def initialize(id:, width:, height:, dummy:)
        @id = id
        @width = width
        @height = height
        @dummy = dummy
      end

      def dummy?
        @dummy
      end
    end
  end
end
