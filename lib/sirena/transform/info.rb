# frozen_string_literal: true

require_relative 'base'
require_relative '../diagram/info'

module Sirena
  module Transform
    # Info diagram transformer for converting info models to renderable structure.
    #
    # Info diagrams have no complex layout requirements - they simply display
    # an informational message. This transformer prepares basic data for rendering.
    #
    # @example Transform an info diagram
    #   transform = InfoTransform.new
    #   data = transform.to_graph(info_diagram)
    class InfoTransform < Base
      # Converts an info diagram to a simple data structure.
      #
      # Info diagrams don't need layout computation. This method validates
      # the diagram and returns a structure for the renderer.
      #
      # @param diagram [Diagram::Info] the info diagram to transform
      # @return [Hash] data structure for rendering
      # @raise [TransformError] if diagram is invalid
      def to_graph(diagram)
        raise TransformError, 'Invalid diagram' unless diagram.valid?

        {
          id: diagram.id || 'info',
          title: diagram.title,
          show_info: diagram.show_info || false,
          metadata: {
            diagram_type: :info
          }
        }
      end
    end
  end
end