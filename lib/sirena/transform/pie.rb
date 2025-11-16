# frozen_string_literal: true

require_relative 'base'
require_relative '../diagram/pie'

module Sirena
  module Transform
    # Pie chart transformer for converting pie models to renderable structure.
    #
    # Unlike flowcharts and sequence diagrams which require complex layout
    # computation, pie charts have a fixed circular layout. This transformer
    # simply validates and prepares the diagram data for direct rendering.
    #
    # @example Transform a pie chart
    #   transform = PieTransform.new
    #   data = transform.to_graph(pie_diagram)
    class PieTransform < Base
      # Converts a pie diagram to a simple data structure.
      #
      # Pie charts don't need graph layout computation since they have
      # a fixed circular layout. This method validates the diagram and
      # returns a simple structure for the renderer.
      #
      # @param diagram [Diagram::Pie] the pie diagram to transform
      # @return [Hash] data structure for rendering
      # @raise [TransformError] if diagram is invalid
      def to_graph(diagram)
        raise TransformError, 'Invalid diagram' unless diagram.valid?

        {
          id: diagram.id || 'pie',
          title: diagram.title,
          show_data: diagram.show_data || false,
          acc_title: diagram.acc_title,
          acc_description: diagram.acc_description,
          slices: transform_slices(diagram),
          metadata: {
            total_value: diagram.total_value,
            slice_count: (diagram.slices || []).length
          }
        }
      end

      private

      def transform_slices(diagram)
        return [] if diagram.slices.nil? || diagram.slices.empty?

        diagram.slices.map.with_index do |slice, index|
          {
            id: "slice_#{index}",
            label: slice.label,
            value: slice.value,
            percentage: slice.percentage(diagram.total_value),
            angle: diagram.slice_angle(slice),
            index: index
          }
        end
      end
    end
  end
end