# frozen_string_literal: true

require_relative "scene"

module Sirena
  module Notation
    module PlantUML
      # The small box PlantUML draws at the class end of a link written with
      # a bracketed qualifier, `A [key: string] *-- B`: a one-line box
      # outside the class, centred on a steep link and beside a flat one,
      # with the link starting at its far side.
      module QualifierBox
        extend self

        # Ratios to the font size, measured on PlantUML 1.2026.6.
        HEIGHT = 18.4883 / 14.0
        BASELINE = 14.5352 / 14.0
        INSET = 2.0
        OVERLAP = 0.5
        private_constant :HEIGHT, :BASELINE, :INSET, :OVERLAP

        Placed = Data.define(:box, :clearance)

        # @param content [String] the qualifier's text
        # @param endpoint [Array<Float>] where the link meets the class
        # @param outward [Array<Float>] unit vector from the class along the
        #   link
        # @param text_width [Float] the text's width at `size`
        # @param size [Float] the font size
        # @return [Placed] the box and how far along the link it pushes the
        #   link's start
        def place(content, endpoint, outward, text_width, size)
          width = text_width + (2 * INSET)
          height = size * HEIGHT
          steep = outward[1].abs >= outward[0].abs
          left, top, reach = if steep
                               across(endpoint, outward[1], width, height)
                             else
                               beside(endpoint, outward[0], width, height)
                             end
          Placed.new(
            box: build(content, [left, top, width, height], size),
            clearance: reach / outward[steep ? 1 : 0].abs,
          )
        end

        private

        def across(endpoint, sign, width, height)
          ex, ey = endpoint
          top = sign.positive? ? ey - OVERLAP : ey - height + OVERLAP
          [ex - (width / 2), top, height - OVERLAP]
        end

        def beside(endpoint, sign, width, height)
          ex, ey = endpoint
          left = sign.positive? ? ex - OVERLAP : ex - width + OVERLAP
          [left, ey - (height / 2), width - OVERLAP]
        end

        def build(content, (left, top, width, height), size)
          text = Scene::Text.new(content: content, x: left + INSET,
                                 y: top + (size * BASELINE),
                                 role: "qualifier", anchor: "start")
          Scene::Box.new(id: "qualifier", x: left, y: top, width: width,
                         height: height, texts: [text], separators: [],
                         kind: "qualifier")
        end
      end
    end
  end
end
