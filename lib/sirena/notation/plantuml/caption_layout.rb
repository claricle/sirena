# frozen_string_literal: true

require_relative "caption_rows"
require_relative "scene"

module Sirena
  module Notation
    module PlantUML
      # Places a diagram's captions around an already laid out Scene: header
      # and title above it, legend, caption and footer below it, each on its
      # own row. The content keeps its coordinates and moves as a whole by
      # the Scene's `content_x` and `content_y`.
      class CaptionLayout
        PADDING = 5.0
        SMALL = %i[header footer].freeze
        SMALL_SIZE = 10.0
        LEGEND_FILL = "#DDDDDD"
        SMALL_COLOUR = "#888888"
        private_constant :PADDING, :SMALL, :SMALL_SIZE, :LEGEND_FILL,
                         :SMALL_COLOUR

        # @param diagram [Diagram]
        # @param normal_size [Float] the font size of a title, caption or
        #   legend that the style does not set
        # @param measure [#call] width of a text given the text and its size
        def initialize(diagram, normal_size:, measure:)
          @diagram = diagram
          @normal_size = normal_size
          @measure = measure
        end

        # @param scene [Scene] the content, freshly built: it is resized and
        #   given the panels in place
        # @return [Scene] the same Scene, as large as content and captions
        def dress(scene)
          panels = sized_panels
          return scene if panels.empty? && @diagram.style.background.nil?

          width = canvas_width(scene, panels)
          settle(scene, width, CaptionRows.new(panels, width, scene.height))
          scene.background = @diagram.style.background
          scene
        end

        private

        # The old width is read before it is replaced.
        def settle(scene, width, rows)
          scene.content_x = (width - scene.width) / 2
          scene.content_y = rows.content_y
          scene.width = width
          scene.height = rows.bottom_edge
          scene.panels = rows.panels
        end

        def canvas_width(scene, panels)
          widest = panels.map(&:width).max.to_f
          [scene.width, widest + (CaptionRows::GAP * 2)].max
        end

        def sized_panels
          @diagram.captions.map { |caption| panel(caption) }
        end

        def panel(caption)
          kind = caption.kind
          rule = @diagram.style.rule(kind)
          size = size_of(kind, rule)
          Scene::Panel.new(
            id: "caption-#{kind}", kind: kind.to_s, font_size: size,
            content: caption.text, **extent_of(caption.text, size),
            **look_of(kind, rule)
          )
        end

        def extent_of(text, size)
          { width: @measure.call(text, size) + (PADDING * 2),
            height: (size * 1.2) + (PADDING * 2) }
        end

        def look_of(kind, rule)
          { bordered: kind == :legend, bold: kind == :title,
            fill: rule[:background] || (LEGEND_FILL if kind == :legend),
            colour: rule[:colour] || (SMALL_COLOUR if SMALL.include?(kind)) }
        end

        def size_of(kind, rule)
          (rule[:size] || default_size(kind)).to_f
        end

        def default_size(kind)
          SMALL.include?(kind) ? SMALL_SIZE : @normal_size
        end
      end
    end
  end
end
