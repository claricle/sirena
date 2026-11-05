# frozen_string_literal: true

require_relative "../drawing"
require_relative "placement"
require_relative "shapes"

module Sirena
  module Notation
    module PlantUML
      module Network
        # Stacks the networks as horizontal bars and hangs each node's box
        # below the first bar it belongs to, with a line to every bar after.
        class Layout
          include Drawing::Pen

          MARGIN = 20.0
          BAR = 8.0
          GAP = 120.0
          TOP = 44.0
          BOX_HEIGHT = 40.0
          LINK = 30.0
          COLUMN_PAD = 40.0
          SHADE = "#E5E5E5"
          DEFAULT_BAR = "#E2E2F0"
          COLOR = /\A#?[A-Za-z0-9]+\z/
          private_constant :MARGIN, :BAR, :GAP, :TOP, :BOX_HEIGHT, :LINK,
                           :COLUMN_PAD, :SHADE, :DEFAULT_BAR, :COLOR

          # @param diagram [Diagram]
          # @return [Drawing::Scene]
          def call(diagram, **)
            @diagram = diagram
            @placement = Placement.new(diagram)
            @column = column_width
            draw_all
            scene(bars_width + (2 * MARGIN), canvas_height)
          end

          private

          def draw_all
            @diagram.networks.each_index do |index|
              draw_groups(index)
              draw_bar(index)
            end
            @placement.spans.each { |span| draw_node(span) }
          end

          def column_width
            widest = @diagram.shapes.keys.map { |name| text_width(name) }.max
            [widest.to_f + 40.0, 80.0].max + COLUMN_PAD
          end

          def bars_width
            @placement.columns * @column
          end

          def canvas_height
            [bar_top(last_index) + bottom_room, 2 * MARGIN].max
          end

          def bar_top(index)
            TOP + (index * (BAR + GAP))
          end

          def bottom_room
            hangs = @placement.spans.any? { |s| s.entry == last_index }
            BAR + (hangs ? LINK + BOX_HEIGHT + MARGIN : MARGIN)
          end

          def last_index
            @diagram.networks.size - 1
          end

          def box_of(span)
            left = MARGIN + (span.column * @column) + (COLUMN_PAD / 2)
            Drawing::Box.new(left, bar_top(span.entry) + BAR + LINK,
                             @column - COLUMN_PAD, BOX_HEIGHT)
          end

          def draw_bar(index)
            network = @diagram.networks[index]
            top = bar_top(index)
            rect(MARGIN, top, bars_width, BAR, fill: paint(network.color))
            text(network.name, MARGIN, top - 26)
            text(network.address, MARGIN, top - 12) if network.address
          end

          def paint(color)
            color&.match?(COLOR) ? color : DEFAULT_BAR
          end

          def draw_node(span)
            box = box_of(span)
            draw_links(span, box)
            shape = @diagram.shapes[span.name]
            Shapes.draw(self, shape, box)
            text(span.name, box.centre, Shapes.label_middle(shape, box),
                 anchor: "middle")
            draw_addresses(span, box)
          end

          def draw_links(span, box)
            x = box.centre
            line(x, bar_top(span.entry) + BAR, x, box.top)
            line(x, box.bottom, x, bar_top(span.exit)) if span.exit > span.entry
          end

          def draw_addresses(span, box)
            @diagram.networks.each_with_index do |network, index|
              member = network.nodes.find { |m| m.name == span.name }
              next unless member&.address

              entries = member.address.split(/\s*,\s*/)
              draw_address(entries, box.centre, index, index == span.entry)
            end
          end

          def draw_address(entries, centre, index, below)
            entries.each_with_index do |entry, row|
              y = address_y(bar_top(index), below, row, entries.size)
              text(entry, centre + 4, y, size: 10)
            end
          end

          def address_y(top, below, row, count)
            return top + BAR + 8 + (row * 11) if below

            top - 8 - ((count - 1 - row) * 11)
          end

          def draw_groups(index)
            @diagram.networks[index].groups.each do |group|
              spans = group.names.map { |name| @placement[name] }
              spans = spans.select { |span| span.entry == index }
              draw_group(spans, group) if spans.any?
            end
          end

          def draw_group(spans, group)
            area = surround(spans.map { |span| box_of(span) })
            rect(area.left, area.top, area.width, area.height,
                 fill: paint(group.color || SHADE), stroke: "none")
          end

          def surround(boxes)
            left = boxes.map(&:left).min - 10
            Drawing::Box.new(left, boxes.first.top - 10,
                             boxes.map(&:right).max + 10 - left,
                             BOX_HEIGHT + 20)
          end
        end
      end
    end
  end
end
