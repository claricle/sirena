# frozen_string_literal: true

require_relative "base"

module Sirena
  module Diagram
    # Represents a radar/spider chart diagram
    class RadarChart < Base
      attr_accessor :title, :acc_title, :acc_descr, :axes, :curves, :options

      def initialize
        super
        @axes = []
        @curves = []
        @options = {}
      end

      # Returns the diagram type identifier.
      #
      # @return [Symbol] :radar
      def diagram_type
        :radar
      end

      # Radar charts have no validation rules yet. See TODO.foundation's
      # corpus burndown for real validation; this is deliberately trivial.
      #
      # @return [Boolean] true
      def valid?
        true
      end
    end

    # Represents an axis in a radar chart
    class RadarAxis
      attr_accessor :id, :label

      def initialize(id, label = nil)
        @id = id
        @label = label || id
      end
    end

    # Represents a data curve/dataset in a radar chart
    class RadarCurve
      attr_accessor :id, :label, :values

      def initialize(id, label = nil)
        @id = id
        @label = label || id
        @values = {}
      end

      # Add a value for an axis
      def add_value(axis_id, value)
        @values[axis_id] = value.to_f
      end

      # Get value for an axis
      def value_for(axis_id)
        @values[axis_id] || 0.0
      end
    end
  end
end