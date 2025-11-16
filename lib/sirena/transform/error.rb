# frozen_string_literal: true

require_relative 'base'
require_relative '../diagram/error'

module Sirena
  module Transform
    # Error diagram transformer for converting error models to renderable structure.
    #
    # Error diagrams have no complex layout requirements - they simply display
    # an error message. This transformer prepares basic data for rendering.
    #
    # @example Transform an error diagram
    #   transform = ErrorTransform.new
    #   data = transform.to_graph(error_diagram)
    class ErrorTransform < Base
      # Converts an error diagram to a simple data structure.
      #
      # Error diagrams don't need layout computation. This method validates
      # the diagram and returns a structure for the renderer.
      #
      # @param diagram [Diagram::Error] the error diagram to transform
      # @return [Hash] data structure for rendering
      # @raise [TransformError] if diagram is invalid
      def to_graph(diagram)
        raise TransformError, 'Invalid diagram' unless diagram.valid?

        {
          id: diagram.id || 'error',
          title: diagram.title,
          message: diagram.message,
          metadata: {
            diagram_type: :error
          }
        }
      end
    end
  end
end