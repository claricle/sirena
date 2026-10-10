# frozen_string_literal: true

require_relative "scene"

module Sirena
  module Notation
    module PlantUML
      # Places a diagram's captions around an already laid out Scene: header
      # and title above it, legend, caption and footer below it, each on its
      # own row. The content keeps its coordinates and moves as a whole by
      # the Scene's `content_x` and `content_y`.
      class CaptionLayout
        GAP = 10.0
        PADDING = 5.0
        TOP = %i[header title].freeze
        BOTTOM = %i[legend caption footer].freeze
        SMALL = %i[header footer].freeze
        SMALL_SIZE = 10.0
        LEGEND_FILL = "#DDDDDD"
        SMALL_COLOUR = "#888888"
        private_constant :GAP, :PADDING, :TOP, :BOTTOM, :SMALL, :SMALL_SIZE,
                         :LEGEND_FILL, :SMALL_COLOUR

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

          width = [scene.width, panels.map(&:width).max.to_f + (GAP * 2)].max
          top = place(panels, TOP, width, GAP)
          content_y = top.empty? ? 0.0 : top.last.y + top.last.height
          below = content_y + scene.height
          bottom = place(panels, BOTTOM, width, below)
          scene.content_x = (width - scene.width) / 2
          scene.content_y = content_y
          scene.width = width
          scene.height = bottom_edge(bottom, below)
          scene.panels = top + bottom
          scene.background = @diagram.style.background
          scene
        end

        private

        def sized_panels
          @diagram.captions.map { |caption| panel(caption) }
        end

        def panel(caption)
          kind = caption.kind
          rule = @diagram.style.rule(kind)
          size = (rule[:size] || default_size(kind)).to_f
          width = @measure.call(caption.text, size) + (PADDING * 2)
          Scene::Panel.new(
            id: "caption-#{kind}", kind: kind.to_s, width: width,
            height: (size * 1.2) + (PADDING * 2), font_size: size,
            fill: rule[:background] || (LEGEND_FILL if kind == :legend),
            bordered: kind == :legend, bold: kind == :title,
            colour: rule[:colour] || (SMALL_COLOUR if SMALL.include?(kind)),
            content: caption.text
          )
        end

        def default_size(kind)
          SMALL.include?(kind) ? SMALL_SIZE : @normal_size
        end

        # Stacks the kinds in `order` that are present, top to bottom from
        # `start`, and returns them positioned.
        def place(panels, order, width, start)
          cursor = start
          order.filter_map do |kind|
            panel = panels.find { |item| item.kind == kind.to_s }
            next unless panel

            positioned = at(panel, width, cursor)
            cursor += panel.height + GAP
            positioned
          end
        end

        def at(panel, width, top)
          left = (width - panel.width) / 2
          left = width - GAP - panel.width if panel.kind == "header"
          panel.tap do |item|
            item.x = left
            item.y = top
          end
        end

        def bottom_edge(bottom, below)
          bottom.empty? ? below : bottom.last.y + bottom.last.height + GAP
        end
      end
    end
  end
end
