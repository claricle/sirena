# frozen_string_literal: true

require_relative "../drawing"
require_relative "shapes"

module Sirena
  module Notation
    module PlantUML
      module Network
        # Where the bars, the rows of boxes under them and the boxes
        # themselves fall, in the JAR's measures.
        class Grid
          # One bar and the row of nodes hung from it: `top` is the bar's;
          # `level` and `height` the row's; `after` where the next bar's
          # top falls.
          Row = Struct.new(:top, :spans, :level, :height, :bottom, :after)

          LEFT = 5.0
          BAR = 5.0
          INSET = 15.0
          COLUMN_GAP = 30.0
          MIN_BAR = 70.0
          # Space between a bar and the row under it, and between a row and
          # the next bar; every address on a node's lines widens both.
          ABOVE = 30.0
          BELOW = 35.0
          LABEL_ROOM = 6.4775
          # Where a bar sits against its name's baseline.
          BAR_RISE = 7.0352
          NAME_STEP = 14.1328
          FIRST_BASELINE = 16.6016
          TAIL = 47.75
          BARE_TAIL = 51.15
          private_constant :INSET, :COLUMN_GAP, :MIN_BAR, :ABOVE, :BELOW,
                           :LABEL_ROOM, :BAR_RISE, :FIRST_BASELINE, :TAIL,
                           :BARE_TAIL

          # @return [Float] x where the bars start
          attr_reader :left
          # @return [Float] the bars' width
          attr_reader :bars

          # @param diagram [Diagram]
          # @param placement [Placement]
          def initialize(diagram, placement)
            @diagram = diagram
            @placement = placement
            @left = LEFT + label_width + LEFT
            @sizes = diagram.shapes.to_h do |name, shape|
              [name, Shapes.size(shape, face(name))]
            end
            @widths = column_widths
            @bars = bar_width
            @rows = build_rows
          end

          # @return [Row] the bar of a network and the row under it
          def row(index)
            @rows.fetch(index)
          end

          # @return [Drawing::Box]
          def box(span)
            width, height = @sizes.fetch(span.name)
            Drawing::Box.new(box_left(span, width), box_top(span, height),
                             width, height)
          end

          # @return [Float] y of the name's baseline at a network's bar
          def baseline(index)
            row(index).top + BAR_RISE - lift(@diagram.networks[index])
          end

          # @return [Float] the canvas' width and height
          def canvas
            [(@left + @bars + 6).floor + 1, foot.ceil]
          end

          private

          def box_left(span, width)
            slot_left(span.column) + ((@widths[span.column] - width) / 2)
          end

          def box_top(span, height)
            row = row(span.entry)
            row.level + ((row.height - height) / 2)
          end

          # Where the canvas ends: under the last row, or under a last bar
          # that has none.
          def foot
            last = @rows.last
            return last.bottom + TAIL if last.spans.any?

            last.top + BAR + BARE_TAIL
          end

          def face(text)
            Drawing::Face.width(text, size: 12)
          end

          def lift(network)
            network.address ? NAME_STEP / 2 : 0
          end

          def label_width
            texts = @diagram.networks.flat_map { |n| [n.name, n.address] }
            texts.compact.map { |text| face(text) }.max.to_f
          end

          def column_widths
            Array.new(@placement.columns) do |column|
              spans = @placement.spans.select { |s| s.column == column }
              spans.map { |s| @sizes.fetch(s.name).first }.max
            end
          end

          def bar_width
            inner = @widths.sum + (COLUMN_GAP * (@widths.size - 1))
            [INSET + inner + INSET, MIN_BAR].max
          end

          def slot_left(column)
            @left + INSET + @widths.first(column).sum + (COLUMN_GAP * column)
          end

          def build_rows
            top = FIRST_BASELINE - BAR_RISE + lift(@diagram.networks.first)
            @diagram.networks.each_index.map do |index|
              row_at(index, top).tap { |row| top = row.after }
            end
          end

          def row_at(index, top)
            spans = @placement.spans.select { |s| s.entry == index }
            return bare_row(top) if spans.empty?

            hung_row(top, spans)
          end

          def bare_row(top)
            Row.new(top, [], top + BAR + ABOVE, 0.0, top + BAR,
                    top + BAR + ABOVE + BELOW)
          end

          def hung_row(top, spans)
            height = spans.map { |s| @sizes.fetch(s.name).last }.max
            extra = room(spans)
            level = top + BAR + ABOVE + extra
            Row.new(top, spans, level, height, level + height,
                    level + height + BELOW + extra)
          end

          def room(spans)
            LABEL_ROOM * spans.map { |s| lines(s) }.max
          end

          # How many address lines a node's lines carry in all.
          def lines(span)
            @diagram.networks.sum do |network|
              member = network.nodes.find { |m| m.name == span.name }
              member&.address ? member.address.split(/\s*,\s*/).size : 0
            end
          end
        end
      end
    end
  end
end
