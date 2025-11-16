# frozen_string_literal: true

module Sirena
  module Diagram
    # Represents an XY chart diagram (scatter/line/bar chart)
    class XYChart < Base
      attr_accessor :title, :x_axis, :y_axis, :datasets, :options

      def initialize
        super
        @datasets = []
        @options = {}
      end

      def type
        :xychart
      end

      # Add a dataset to the chart
      def add_dataset(dataset)
        @datasets << dataset
      end
    end

    # Represents an axis configuration
    class XYAxis
      attr_accessor :label, :values, :min, :max, :type

      def initialize
        @type = :numeric # :numeric or :categorical
        @values = []
      end

      # Check if axis has categorical values
      def categorical?
        @type == :categorical
      end

      # Check if axis has numeric range
      def numeric?
        @type == :numeric
      end

      # Get the range of the axis
      def range
        if numeric?
          [@min || 0, @max || 100]
        else
          [0, values.length - 1]
        end
      end
    end

    # Represents a dataset in an XY chart
    class XYDataset
      attr_accessor :id, :label, :chart_type, :values, :color

      def initialize(id, label = nil, chart_type = :line)
        @id = id
        @label = label || id
        @chart_type = chart_type # :line, :bar, :scatter
        @values = []
      end

      # Add a value to the dataset
      def add_value(value)
        @values << value.to_f
      end

      # Set all values at once
      def values=(vals)
        @values = vals.map(&:to_f)
      end
    end
  end
end