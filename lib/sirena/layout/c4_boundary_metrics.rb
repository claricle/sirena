# frozen_string_literal: true

require_relative "c4_text"

module Sirena
  module Layout
    # The heading of a C4 boundary: its name and "[type]" under it. The
    # height is what mermaid's drawInsideBoundary reserves above the first
    # box the boundary holds.
    class C4BoundaryMetrics
      LABEL_FONT_SIZE = 16
      TYPE_FONT_SIZE = 14

      attr_reader :label_offset, :type_offset, :height

      # @param label [String] the boundary name
      # @param type [String, nil] the type, drawn as "[type]"
      def initialize(label:, type: nil)
        @label_offset = 8
        offset = @label_offset + C4Text.height(label.to_s, LABEL_FONT_SIZE)
        @type_offset = type.to_s.empty? ? nil : offset + 5
        @height = @type_offset ? type_bottom(type) : offset
      end

      private

      def type_bottom(type)
        @type_offset + C4Text.height("[#{type}]", TYPE_FONT_SIZE)
      end
    end
  end
end
