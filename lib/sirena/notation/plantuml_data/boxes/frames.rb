# frozen_string_literal: true

require_relative "marks"
require_relative "text"

module Sirena
  module Notation
    module PlantUMLData
      module Boxes
        # The package frames around the boxes of a dotted name: one frame per
        # package path, drawn as PlantUML does with a tab bearing the
        # package's name, enclosing its boxes and the frames inside it.
        class Frames
          PAD = 10.0
          TAB = 22.0
          SLANT = 8.0
          TAB_PAD = 8.0
          # What a frame takes beyond its boxes on the sides that meet a
          # neighbour.
          ROOM = (2 * PAD) + TAB
          Frame = Data.define(:name, :x, :y, :width, :height) do
            def right = x + width
            def bottom = y + height
          end

          # @param frame [Frame]
          # @return [Array<Hash>] the marks of the frame, its tab included
          def self.marks(frame)
            [Marks.rect(frame.x, frame.y, frame.width, frame.height,
                        rx: 2.5, fill: "none"),
             Marks.polygon(tab(frame), fill: Marks::PAPER,
                                       stroke: Marks::INK),
             Marks.text(frame.name, frame.x + TAB_PAD, frame.y + (TAB / 2),
                        bold: true)]
          end

          def self.tab(frame)
            top = frame.y
            right = frame.x + Text.width(frame.name, bold: true) + (2 * TAB_PAD)
            [[frame.x, top], [right, top], [right + SLANT, top + SLANT],
             [right + SLANT, top + TAB], [frame.x, top + TAB]]
          end
          private_class_method :tab

          # @param tables [Array<Table>]
          # @param rects [Hash{String => #x, #y, #right, #bottom}] a box's
          #   place by table id
          def initialize(tables, rects)
            @tables = tables
            @rects = rects
          end

          # @return [Hash{Array<String> => Frame}] a frame by package path,
          #   the innermost first
          def frames
            by_depth = paths.sort_by { |path| -path.size }
            by_depth.each_with_object({}) do |path, made|
              made[path] = frame(path, made)
            end
          end

          private

          def paths
            @tables.flat_map do |table|
              (1..table.group.size).map { |size| table.group.first(size) }
            end.uniq
          end

          def frame(path, made)
            parts = members(path, made)
            left = parts.map(&:x).min - PAD
            top = parts.map(&:y).min - PAD - TAB
            Frame.new(name: path.last, x: left, y: top,
                      width: reach(parts, :right) - left,
                      height: reach(parts, :bottom) - top)
          end

          def reach(parts, side)
            parts.map(&side).max + PAD
          end

          # The boxes directly in the package and the frames just inside it.
          def members(path, made)
            boxes = @tables.select { |table| table.group == path }
              .map { |table| @rects.fetch(table.id) }
            [*boxes, *inside(path, made)]
          end

          def inside(path, made)
            made.filter_map do |other, frame|
              next unless other.size == path.size + 1

              frame if other.first(path.size) == path
            end
          end
        end
      end
    end
  end
end
