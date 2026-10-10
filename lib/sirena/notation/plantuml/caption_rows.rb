# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # Stacks sized caption panels into the rows above and below the
      # diagram content: header and title above it, legend, caption and
      # footer below it, each kind on its own row.
      class CaptionRows
        GAP = 10.0
        TOP = %i[header title].freeze
        BOTTOM = %i[legend caption footer].freeze
        private_constant :TOP, :BOTTOM

        # @param panels [Array<Scene::Panel>] sized, not yet positioned
        # @param width [Float] the width of the whole picture
        # @param content_height [Float] the height of the diagram content
        def initialize(panels, width, content_height)
          @panels = panels
          @width = width
          @top = stack(TOP, GAP)
          @content_y = @top.empty? ? 0.0 : @top.last.y + @top.last.height
          @below = @content_y + content_height
          @bottom = stack(BOTTOM, @below)
        end

        # @return [Float] where the diagram content starts
        attr_reader :content_y

        # @return [Array<Scene::Panel>] every panel, positioned
        def panels
          @top + @bottom
        end

        # @return [Float] the height of the whole picture
        def bottom_edge
          @bottom.empty? ? @below : @bottom.last.y + @bottom.last.height + GAP
        end

        private

        # Stacks the kinds in `order` that are present, top to bottom from
        # `start`, and returns them positioned.
        def stack(order, start)
          cursor = start
          order.filter_map do |kind|
            panel = @panels.find { |item| item.kind == kind.to_s }
            next unless panel

            positioned = at(panel, cursor)
            cursor += panel.height + GAP
            positioned
          end
        end

        def at(panel, top)
          left = (@width - panel.width) / 2
          left = @width - GAP - panel.width if panel.kind == "header"
          panel.tap do |item|
            item.x = left
            item.y = top
          end
        end
      end
    end
  end
end
