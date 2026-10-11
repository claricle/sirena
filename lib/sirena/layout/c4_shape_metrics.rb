# frozen_string_literal: true

require_relative "c4_text"

module Sirena
  module Layout
    # Size of a C4 person, system, container or component box and the
    # offsets, from its top, of what is drawn inside it. A port of
    # mermaid's drawC4ShapeArray: every offset below is the number that
    # function adds, in the order it adds them.
    class C4ShapeMetrics
      PADDING = 20
      MIN_WIDTH = 216
      MIN_HEIGHT = 60
      IMAGE_SIZE = 48
      LABEL_FONT_SIZE = 16
      BODY_FONT_SIZE = 14
      STEREOTYPE_FONT_SIZE = 12

      attr_reader :stereotype_offset, :image_offset, :label_offset,
                  :technology_offset, :description_offset, :width, :height

      # @param label [String] the element name
      # @param technology [String, nil] drawn as "[technology]"
      # @param description [String, nil] drawn below the name
      # @param person [Boolean] reserves room for the person icon
      def initialize(label:, technology: nil, description: nil, person: false,
                     font_sizes: {})
        @label = label.to_s
        @technology = technology.to_s
        @description = description.to_s
        @person = person
        @label_font_size = font_sizes.fetch(:label, LABEL_FONT_SIZE)
        @body_font_size = font_sizes.fetch(:body, BODY_FONT_SIZE)
        @stereotype_font_size =
          font_sizes.fetch(:stereotype, STEREOTYPE_FONT_SIZE)
        measure
      end

      private

      def measure
        @stereotype_offset = PADDING
        offset = PADDING + @stereotype_font_size + 2 - 4
        offset = place_image(offset)
        offset = place_label(offset)
        offset = place_technology(offset)
        place_description(offset)
      end

      def place_image(offset)
        return offset unless @person

        @image_offset = offset
        offset + IMAGE_SIZE
      end

      def place_label(offset)
        @label_offset = offset + 8
        @label_offset + C4Text.height(@label, @label_font_size)
      end

      def place_technology(offset)
        return offset if @technology.empty?

        @technology_offset = offset + 5
        @technology_offset + C4Text.height(bracketed, @body_font_size)
      end

      def place_description(offset)
        rect_width = C4Text.width(@label, @label_font_size)
        rect_height = offset
        unless @description.empty?
          rect_width = [rect_width, description_width].max
          rect_height = description_bottom(offset)
        end
        @width = [rect_width + PADDING, MIN_WIDTH].max
        @height = [rect_height, MIN_HEIGHT].max
      end

      def description_bottom(offset)
        @description_offset = offset + 20
        text_height = C4Text.height(@description, @body_font_size)
        bottom = @description_offset + text_height
        bottom - (C4Text.lines(@description).length * 5)
      end

      def description_width
        C4Text.width(@description, @body_font_size)
      end

      def bracketed
        "[#{@technology}]"
      end
    end
  end
end
