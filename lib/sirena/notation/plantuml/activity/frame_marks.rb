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
          LANE_RULE = "#000000"
          WARNING_PAPER = "#FFFFCC"
          WARNING_INK = "#FFDD88"
          private_constant :PARTITION_PAD, :LANE_FLOOR,
                           :LANE_RULE, :WARNING_PAPER, :WARNING_INK

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

          # PlantUML's notices, in a yellow box under the title: one
          # monospace line each.
          def warnings
            rows = @diagram.warnings
            return if rows.empty?

            left = Layout::MARGIN
            top = left + (@diagram.title ? Placement::TITLE_HEIGHT : 0)
            @canvas.rect(notice_box(rows, left, top), fill: WARNING_PAPER,
                                                      stroke: WARNING_INK,
                                                      radius: 2.5,
                                                      role: :warning)
            @canvas.mono_lines(rows, [left + 7, top + 10.6406],
                               pitch: Placement::WARNING_PITCH)
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

          def notice_box(rows, left, top)
            Box.spanning(left, top, left + @canvas.mono_width(rows) + 10,
                         top + (Placement::WARNING_PITCH * rows.size) - 5)
          end

          def lane(band, ceiling, floor)
            left = band[:left]
            right = band[:right]
            @canvas.rect(Box.spanning(left, ceiling, right, floor),
                         fill: band[:colour] || "none")
            [left, right].each do |x_pos|
              @canvas.path([[x_pos, ceiling], [x_pos, floor]],
                           stroke: LANE_RULE, width: 1.5)
            end
            @canvas.lines([band[:name]], [(left + right) / 2, ceiling + 20],
                          anchor: "middle", size: Placement::LANE_TITLE)
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
