# frozen_string_literal: true

require 'lutaml/model'
require_relative 'base'

module Sirena
  module Diagram
    # Represents a slice in a pie chart.
    #
    # A slice represents a data point with a label and numeric value.
    class PieSlice < Lutaml::Model::Serializable
      # Label/name for this slice
      attribute :label, :string

      # Numeric value for this slice (can be integer or decimal)
      attribute :value, :float

      # Validates the slice has required attributes.
      #
      # @return [Boolean] true if slice is valid
      def valid?
        !label.nil? && !label.empty? && !value.nil?
      end

      # Calculate percentage of total.
      #
      # @param total [Float] the total value of all slices
      # @return [Float] percentage (0-100)
      def percentage(total)
        return 0.0 if total.zero?

        (value.to_f / total) * 100.0
      end
    end

    # Pie chart diagram model.
    #
    # Represents a complete pie chart with labeled slices showing
    # proportional data distribution. Pie charts are useful for showing
    # part-to-whole relationships.
    #
    # @example Creating a simple pie chart
    #   pie = Pie.new
    #   pie.title = 'Sales Report'
    #   pie.slices << PieSlice.new(label: 'Apples', value: 42.5)
    #   pie.slices << PieSlice.new(label: 'Oranges', value: 30.2)
    #   pie.slices << PieSlice.new(label: 'Bananas', value: 27.3)
    class Pie < Base
      # Collection of data slices in the pie chart
      attribute :slices, PieSlice, collection: true, default: -> { [] }

      # Whether to show data values on the chart
      attribute :show_data, :boolean, default: -> { false }

      # Accessibility title (for screen readers)
      attribute :acc_title, :string

      # Accessibility description (for screen readers)
      attribute :acc_description, :string

      # Returns the diagram type identifier.
      #
      # @return [Symbol] :pie
      def diagram_type
        :pie
      end

      # Validates the pie chart structure.
      #
      # A pie chart is valid if:
      # - All slices (if any) are valid
      # - All slice values are numeric
      #
      # Note: Empty pie charts are allowed for parsing tests
      #
      # @return [Boolean] true if pie chart is valid
      def valid?
        return true if slices.nil? || slices.empty?

        slices.all?(&:valid?)
      end

      # Calculate total value of all slices.
      #
      # @return [Float] sum of all slice values
      def total_value
        slices.sum(&:value)
      end

      # Get slices with their calculated percentages.
      #
      # @return [Array<Hash>] array of hashes with :slice and :percentage
      def slices_with_percentages
        total = total_value
        slices.map do |slice|
          {
            slice: slice,
            percentage: slice.percentage(total)
          }
        end
      end

      # Calculate angle in degrees for a slice.
      #
      # @param slice [PieSlice] the slice to calculate angle for
      # @return [Float] angle in degrees (0-360)
      def slice_angle(slice)
        total = total_value
        return 0.0 if total.zero?

        (slice.value / total) * 360.0
      end
    end
  end
end