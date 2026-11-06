# frozen_string_literal: true

require_relative "../../../svg"
require_relative "entity_metrics"

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # Draws an entity: a header with the "E" spot and the name, then
        # one compartment per field section. A key field (`*name`) carries a
        # bullet.
        class EntityShape
          STROKE = "#181818"
          # The reference draws the frame of an entity with a hairline and
          # rounds its corners.
          FRAME_WIDTH = "0.5"
          CORNER = 2.5
          Metrics = EntityMetrics

          # @param placed [Placed]
          def initialize(placed)
            @p = placed
            @sections = placed.node.sections || []
          end

          # @return [Array<Svg::Element>]
          def elements
            [shape(Svg::Rect, x: @p.x, y: @p.y, width: @p.width,
                              height: @p.height, fill: "#F1F1F1",
                              rx: CORNER, ry: CORNER,
                              stroke_width: FRAME_WIDTH),
             *header, *compartments]
          end

          private

          def header
            left = @p.x + ((@p.width - span) / 2)
            [*spot(left + Metrics::SPOT, mid),
             label(left + Metrics::SPOT_ROOM, mid + 4, name)]
          end

          def name
            @p.node.lines.join(" ")
          end

          def mid
            @p.y + (Metrics::HEADER / 2)
          end

          def span
            Metrics::SPOT_ROOM + Metrics.text_width(name)
          end

          def spot(across, down)
            [shape(Svg::Circle, cx: across, cy: down, r: Metrics::SPOT,
                                fill: "#ADD1B2"),
             label(across, down + 4, "E", anchor: "middle", weight: "bold")]
          end

          def compartments
            top = @p.y + Metrics::HEADER
            @sections.each_with_index.flat_map do |rows, index|
              parts = [rule(top, index.zero? ? "0.5" : "1"), *fields(rows, top)]
              top += Metrics.section_height(rows)
              parts
            end
          end

          def fields(rows, top)
            rows.each_with_index.flat_map do |field, row|
              base = top + Metrics::SECTION_PAD + (row * Metrics::ROW)
              [*bullet(field, base),
               label(@p.x + Metrics::INDENT, base + 11, field.text)]
            end
          end

          def bullet(field, base)
            return [] unless field.key

            [shape(Svg::Circle, cx: @p.x + 10, cy: base + 5, r: 3,
                                fill: "#000000")]
          end

          def rule(down, width)
            shape(Svg::Line, x1: @p.x, x2: @p.x + @p.width, y1: down,
                             y2: down, stroke_width: width)
          end

          def shape(type, **attrs)
            build(type, { stroke: STROKE, stroke_width: "1" }.merge(attrs))
          end

          def label(across, down, content, anchor: "start", weight: nil)
            build(Svg::Text, x: across, y: down, content: content,
                             text_anchor: anchor, font_family: "sans-serif",
                             font_size: Metrics::FONT_SIZE.to_s,
                             font_weight: weight, fill: "#000000")
          end

          def build(type, attrs)
            type.new.tap do |node|
              attrs.each { |key, value| node.public_send(:"#{key}=", value) }
            end
          end
        end
      end
    end
  end
end
