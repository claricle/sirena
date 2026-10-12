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
        NESTING_STEP = 8.0
        NESTED_OPEN = 35.0
        RELATION_INSET = 8.0
        TAB_HEIGHT = 22.0
        ICON_WIDTH = 14.0
        private_constant :NESTING_STEP, :NESTED_OPEN, :RELATION_INSET,
                         :TAB_HEIGHT, :ICON_WIDTH

        def self.stack_open(depth)
          stack_space(depth, NESTED_OPEN)
        end

        def self.stack_close(depth)
          stack_space(depth, CLOSE)
        end

        def self.stack_side(depth)
          stack_space(depth, SIDE)
        end

        def self.relation_layout?(diagram)
          package_ids = diagram.packages.map(&:id)
          diagram.relations.one? do |relation|
            package_ids.include?(relation.left) ||
              package_ids.include?(relation.right)
          end
        end

        def self.stack_space(depth, base)
          depth.times.sum { |level| base + (level * NESTING_STEP) }
        end
        private_class_method :stack_space

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
            left, top, right, bottom = edges(
              package, own_edges(package) + inner_edges(package)
            )
            left, right = relation_edges(package, left, right)
            [left, top, right - left, bottom - top]
          end
        end

        def edges(package, rectangles)
          lefts, tops, rights, bottoms = rectangles.transpose
          side, above, below = frame_padding(package)
          [lefts.min - side,
           tops.min - above,
           rights.max + side,
           bottoms.max + below]
        end

        def frame_padding(package)
          return default_padding unless nested_relation_layout?

          increment = descendant_depth(package) * NESTING_STEP
          [SIDE + increment, NESTED_OPEN + increment, CLOSE + increment]
        end

        def default_padding
          [SIDE, OPEN - 6.0, CLOSE - 4.0]
        end

        def nested_relation_layout?
          self.class.relation_layout?(@diagram)
        end

        def descendant_depth(package)
          children = @diagram.packages.select do |item|
            item.parent == package.id
          end
          return 0 if children.empty?

          1 + children.map { |child| descendant_depth(child) }.max
        end

        def relation_edges(package, left, right)
          targets = @diagram.relations.filter_map do |relation|
            external_target(package, relation)
          end
          targets.each do |target|
            centre = target.x + (target.width / 2)
            left = [left, centre - RELATION_INSET].min
            right = [right, centre + RELATION_INSET].max
          end
          [left, right]
        end

        def external_target(package, relation)
          name = if relation.left == package.id
                   relation.right
                 elsif relation.right == package.id
                   relation.left
                 end
          @boxes.find { |box| box.id == name } if name
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
