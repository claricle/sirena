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
        private_constant :TAB_HEIGHT, :ICON_WIDTH

        # @param diagram [Diagram]
        # @param measure [#call] text width in drawing units
        def initialize(diagram, measure)
          @diagram = diagram
          @measure = measure
        end

        # @param boxes [Array<Scene::Box>] the positioned class boxes
        # @return [Array<Scene::Frame>] outer packages before the ones
        #   inside them
        def call(boxes)
          @boxes = boxes
          @bounds = {}
          @diagram.packages.map do |package|
            build(package, bounds_of(package))
          end
        end

        private

        # Left, top, width and height around the package's own boxes and
        # the frames of the packages inside it.
        def bounds_of(package)
          @bounds[package.id] ||= begin
            left, top, right, bottom = edges(own_edges(package) +
              inner_edges(package))
            [left, top, right - left, bottom - top]
          end
        end

        def edges(rectangles)
          lefts, tops, rights, bottoms = rectangles.transpose
          [lefts.min - SIDE, tops.min - OPEN + 6.0,
           rights.max + SIDE, bottoms.max + 12.0]
        end

        def own_edges(package)
          names = @diagram.classes.filter_map do |klass|
            klass.name if klass.package == package.id
          end
          @boxes.select { |box| names.include?(box.id) }.map { |b| edges_of(b) }
        end

        def edges_of(box)
          [box.x, box.y, box.x + box.width, box.y + box.height]
        end

        def inner_edges(package)
          inside = @diagram.packages.select { |p| p.parent == package.id }
          inside.map do |inner|
            left, top, width, height = bounds_of(inner)
            [left, top, left + width, top + height]
          end
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
            tab_width: (tab_width(package) if folder), fill: package.color
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
