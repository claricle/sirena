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
          LANE_FLOOR = 20.0
          LANE_FILL = "#E2E2F0"
          private_constant :PARTITION_PAD, :LANE_FLOOR, :LANE_FILL

          def initialize(diagram, placement, canvas, metrics)
            @diagram = diagram
            @placement = placement
            @canvas = canvas
            @metrics = metrics
          end

          def title
            return unless @diagram.title

            origin = [Layout::MARGIN, Layout::MARGIN + 14]
            @canvas.lines(@diagram.title.split("\n"), origin, weight: "bold",
                                                              size: 14)
          end

          def lanes
            floor = @placement.bottoms.last + LANE_FLOOR
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
                          anchor: "middle", size: Metrics::FONT_SIZE)
          end

          def partition(name, boxes)
            frame = frame_around(boxes, name)
            @canvas.rect(frame, fill: "none", role: :partition)
            @canvas.lines([name],
                          [frame.left + 8,
                           frame.top + @metrics.size(:partition) + 3],
                          role: :partition)
          end

          # The frame is as tall above the nodes as the title is, and wide
          # enough that the title ends before the arrow that enters it.
          def frame_around(boxes, name)
            top = boxes.min_by(&:top)
            left = [boxes.map(&:left).min - PARTITION_PAD,
                    top.cx - title_width(name)].min
            Box.spanning(left, top.top - @placement.head,
                         reach(boxes, :right, :max),
                         reach(boxes, :bottom, :max))
          end

          def reach(boxes, edge, extreme)
            boxes.map(&edge).public_send(extreme) + PARTITION_PAD
          end

          def title_width(name)
            (1.12 * @metrics.text_width([name], role: :partition)) + 12
          end
        end
      end
    end
  end
end
