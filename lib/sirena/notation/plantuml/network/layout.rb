# frozen_string_literal: true

require_relative "../drawing"
require_relative "grid"
require_relative "placement"
require_relative "shapes"

module Sirena
  module Notation
    module PlantUML
      module Network
        # Stacks the networks as horizontal bars with their names at the left
        # and hangs each node's box in a row below the first bar it belongs
        # to, with a line to every bar after. Measures are the JAR's.
        class Layout
          include Drawing::Pen

          BAR = 5.0
          LINE_STEP = 12.9551
          NAME_STEP = 14.1328
          SLOT = 2.0
          SHADE = "#E7E7E7"
          DEFAULT_BAR = "#E2E2F0"
          INK = "#000000"
          COLOR = /\A#?[A-Za-z0-9]+\z/
          private_constant :BAR, :LINE_STEP, :NAME_STEP, :SLOT, :SHADE,
                           :DEFAULT_BAR, :INK, :COLOR

          # @param diagram [Diagram]
          # @return [Drawing::Scene]
          def call(diagram, **)
            @diagram = diagram
            @placement = Placement.new(diagram)
            @grid = Grid.new(diagram, @placement)
            draw_all
            scene(*@grid.canvas)
          end

          private

          def draw_all
            @diagram.networks.each_index do |index|
              draw_groups(index)
              draw_bar(index)
            end
            @placement.spans.each { |span| draw_node(span) }
          end

          def draw_bar(index)
            rect(@grid.left, @grid.row(index).top, @grid.bars, BAR,
                 fill: paint(@diagram.networks[index].color))
            draw_names(@diagram.networks[index], @grid.baseline(index))
          end

          def draw_names(network, baseline)
            name_line(network.name, baseline)
            return unless network.address

            name_line(network.address, baseline + NAME_STEP)
          end

          def name_line(content, baseline)
            text(content, @grid.left - 5, Drawing::Face.middle(baseline, 12),
                 anchor: "end", fill: INK)
          end

          def paint(color)
            color&.match?(COLOR) ? color : DEFAULT_BAR
          end

          def draw_node(span)
            box = @grid.box(span)
            draw_links(span, box)
            shape = @diagram.shapes[span.name]
            Shapes.draw(self, shape, box)
            text(span.name, Shapes.label_x(shape, box),
                 Drawing::Face.middle(Shapes.baseline(shape, box), 12),
                 anchor: "middle", fill: INK)
            draw_addresses(span, box)
          end

          # A node reached through a network that already holds an earlier
          # node hangs its line left of its centre; the others, right.
          def link_x(span, box)
            box.centre + (carried?(span) ? -SLOT : SLOT)
          end

          def carried?(span)
            @diagram.networks[span.entry].nodes.any? do |member|
              @placement[member.name].entry < span.entry
            end
          end

          def draw_links(span, box)
            x = link_x(span, box)
            line(x, bar_bottom(span.entry), x, box.top)
            return unless span.exit > span.entry

            line(x, box.bottom, x, @grid.row(span.exit).top)
          end

          def bar_bottom(index)
            @grid.row(index).top + BAR
          end

          def draw_addresses(span, box)
            @diagram.networks.each_with_index do |network, index|
              member = network.nodes.find { |m| m.name == span.name }
              next unless member&.address

              draw_address(member.address.split(/\s*,\s*/), span, box, index)
            end
          end

          # The addresses sit along the line between a bar and the box,
          # centred on it, one step apart.
          def draw_address(entries, span, box, index)
            middle = address_middle(span, box, index)
            entries.each_with_index do |entry, row|
              base = middle + ((row - ((entries.size - 1) / 2.0)) * LINE_STEP)
              text(entry, link_x(span, box), Drawing::Face.middle(base, 11),
                   size: 11, anchor: "middle", fill: INK)
            end
          end

          # Where the line that carries the address runs: from the entry
          # bar to the box, or from the box to a later bar.
          def address_middle(span, box, index)
            return ((bar_bottom(index) + box.top) / 2) + 1.66 if
              index == span.entry

            ((box.bottom + @grid.row(index).top) / 2) + 4.15
          end

          def draw_groups(index)
            @diagram.networks[index].groups.each do |group|
              spans = group.names.map { |name| @placement[name] }
              spans = spans.select { |span| span.entry == index }
              draw_group(spans, group, @grid.row(index)) if spans.any?
            end
          end

          def draw_group(spans, group, row)
            left, right = reach(spans.map { |span| @grid.box(span) })
            color = paint(group.color || SHADE)
            rect(left, row.level - 5, right - left, row.height + 10,
                 fill: color, stroke: color)
          end

          # How far a group's shading runs round its boxes.
          def reach(boxes)
            [boxes.map(&:left).min - 5, boxes.map(&:right).max + 5]
          end
        end
      end
    end
  end
end
