# frozen_string_literal: true

module Sirena
  module Layout
    # Path data for the C4 shapes mmdc draws outside the element box: a
    # database cylinder and a queue pill. Each shape is a body path plus a
    # rim path that closes the visible cap.
    class C4ShapeOutline
      CYLINDER_CAP = 10
      PILL_CAP = 5

      # @param shape [String, nil] "database", "queue" or anything else
      # @param left [Numeric] left edge of the element box
      # @param top [Numeric] top edge of the element box
      # @param width [Numeric] element box width
      # @param height [Numeric] element box height
      def initialize(shape:, left:, top:, width:, height:)
        @shape = shape
        @left = Float(left)
        @top = Float(top)
        @width = Float(width)
        @height = Float(height)
      end

      # @return [String, nil] body path data, nil for a plain box
      def body
        outline&.first
      end

      # @return [String, nil] rim path data, nil for a plain box
      def rim
        outline&.last
      end

      private

      def outline
        case @shape
        when "database" then database
        when "queue" then queue
        end
      end

      def database
        half = @width / 2
        [
          "M#{@left},#{@top}c0,-10 #{half},-10 #{half},-10c0,0 #{half},0 " \
          "#{half},10l0,#{@height}c0,10 -#{half},10 -#{half},10" \
          "c0,0 -#{half},0 -#{half},-10l0,-#{@height}",
          "M#{@left},#{@top}c0,10 #{half},10 #{half},10c0,0 #{half},0 " \
          "#{half},-10",
        ]
      end

      def queue
        half = @height / 2
        [
          "M#{@left},#{@top}l#{@width},0c5,0 5,#{half} 5,#{half}" \
          "c0,0 0,#{half} -5,#{half}l-#{@width},0" \
          "c-5,0 -5,-#{half} -5,-#{half}c0,0 0,-#{half} 5,-#{half}",
          "M#{@left + @width},#{@top}c-5,0 -5,#{half} -5,#{half}" \
          "c0,#{half} 5,#{half} 5,#{half}",
        ]
      end
    end
  end
end
