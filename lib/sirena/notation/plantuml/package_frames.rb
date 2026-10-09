# frozen_string_literal: true

require_relative "scene"

module Sirena
  module Notation
    module PlantUML
      # Builds the Scene frame around each package's positioned boxes.
      #
      # The layout gives every package rows of its own, so the bounding box
      # of its boxes holds no other class. `OPEN` and `CLOSE` are the
      # vertical room the layout leaves above and below those rows.
      class PackageFrames
        OPEN = 40.0
        CLOSE = 16.0
        SIDE = 16.0
        TAB_HEIGHT = 22.0
        ICON_WIDTH = 14.0
        private_constant :SIDE, :TAB_HEIGHT, :ICON_WIDTH

        # @param diagram [Diagram]
        # @param measure [#call] text width in drawing units
        def initialize(diagram, measure)
          @diagram = diagram
          @measure = measure
        end

        # @param boxes [Array<Scene::Box>] the positioned class boxes
        # @return [Array<Scene::Frame>]
        def call(boxes)
          @diagram.packages.map do |package|
            members = @diagram.classes.select { |k| k.package == package.id }
            names = members.map(&:name)
            frame(package, boxes.select { |box| names.include?(box.id) })
          end
        end

        private

        def frame(package, boxes)
          left, right = horizontal_bounds(boxes)
          top, bottom = vertical_bounds(boxes)
          build(package, [left, top, right - left, bottom - top])
        end

        def horizontal_bounds(boxes)
          [boxes.map(&:x).min - SIDE,
           boxes.map { |box| box.x + box.width }.max + SIDE]
        end

        def vertical_bounds(boxes)
          [boxes.map(&:y).min - OPEN + 6.0,
           boxes.map { |box| box.y + box.height }.max + 12.0]
        end

        def build(package, (left, top, width, height))
          title = Scene::Text.new(
            content: package.title, role: "package_title", anchor: "start",
            x: left + 10.0 + icon_width(package), y: top + 16.0
          )
          folder = package.shape == :folder
          Scene::Frame.new(
            id: "package-#{package.id}", x: left, y: top, width: width,
            height: height, icon: package.icon, texts: [title],
            tab_width: (tab_width(package) if folder)
          )
        end

        def icon_width(package)
          package.icon ? ICON_WIDTH : 0.0
        end

        def tab_width(package)
          @measure.call(package.title) + 20.0 + icon_width(package)
        end
      end
    end
  end
end
