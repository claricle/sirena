# frozen_string_literal: true

require_relative "box"
require_relative "placement"

module Sirena
  module Notation
    module PlantUML
      module Activity
        # Draws what frames the flow: the title, swimlane bands and
        # partition frames.
        class FrameMarks
          PARTITION_PAD = 10.0
          LANE_FILL = "#E2E2F0"
          private_constant :PARTITION_PAD, :LANE_FILL

          def initialize(diagram, placement, canvas)
            @diagram = diagram
            @placement = placement
            @canvas = canvas
          end

          def title
            return unless @diagram.title

            origin = [Layout::MARGIN, Layout::MARGIN + 14]
            @canvas.lines(@diagram.title.split("\n"), origin, weight: "bold",
                                                              size: 14)
          end

          def lanes
            floor = @placement.bottoms.last + (Placement::RANK_GAP / 2)
            ceiling = @placement.top - Placement::HEADER_HEIGHT
            @placement.bands.each { |band| lane(band, ceiling, floor) }
          end

          def partitions
            @diagram.nodes.filter_map(&:partition).uniq.each do |name|
              members = @diagram.nodes.select { |n| n.partition == name }
              partition(name, members.map { |n| @placement.boxes[n] })
            end
          end

          private

          def lane(band, ceiling, floor)
            left = band[:left]
            right = band[:right]
            @canvas.rect(Box.spanning(left, ceiling, right, floor),
                         fill: "none")
            header = Box.spanning(left, ceiling, right,
                                  ceiling + Placement::HEADER_HEIGHT - 4)
            @canvas.rect(header, fill: band[:colour] || LANE_FILL)
            @canvas.lines([band[:name]], [(left + right) / 2, ceiling + 17],
                          anchor: "middle")
          end

          def partition(name, boxes)
            frame = frame_around(boxes)
            @canvas.rect(frame, fill: "none", role: :partition)
            @canvas.lines([name], [frame.left + 8, frame.top + 15],
                          weight: "bold", role: :partition)
          end

          def frame_around(boxes)
            pad = PARTITION_PAD
            Box.spanning(boxes.map(&:left).min - pad,
                         boxes.map(&:top).min - Placement::PARTITION_PAD,
                         boxes.map(&:right).max + pad,
                         boxes.map(&:bottom).max + pad)
          end
        end
      end
    end
  end
end
