# frozen_string_literal: true

require_relative "bar_columns"
require_relative "column_centres"
require_relative "exits"
require_relative "metrics"
require_relative "row_gaps"

module Sirena
  module Notation
    module PlantUML
      module Activity
        # Puts every node's box at its row and column, then fits each bar to
        # the nodes it joins and each note beside its node.
        class Placement
          LABEL_OFFSET = 5.0
          BARE_LABEL_GAP = 13.0
          NOTE_GAP = 20.0
          TITLE_HEIGHT = 26.0
          HEADER_HEIGHT = 28.0
          PARTITION_BELOW = 10.0
          BAND_PAD = 14.0
          # The height each line of a PlantUML notice adds above the drawing.
          WARNING_PITCH = 21.6406

          # @return [Hash{Node => Box}]
          attr_reader :boxes
          # @return [Array<Float>] the bottom of each row
          attr_reader :bottoms
          # @return [Array<Float>] the space above each row; the first is 0
          attr_reader :gaps
          # @return [Hash{Node => Array<Array(Note, Box)>}]
          attr_reader :notes
          # @return [Float] the top of the first row
          attr_reader :top
          # @return [Array<Hash>] a name, colour, left and right per lane
          attr_reader :bands

          def initialize(diagram, ranking, columns, margin, metrics)
            @diagram = diagram
            @ranking = ranking
            @columns = columns
            @metrics = metrics
            @boxes = diagram.nodes.to_h { |n| [n, metrics.box_for(n)] }
            @top = margin + header_height
            lay_out(margin)
          end

          # @return [Float] room above a partition's nodes for its title
          def head
            @metrics.size(:partition) + 10.0
          end

          private

          def lay_out(margin)
            place_columns(margin)
            @gaps = row_gaps
            place_rows
            fit_bars
            place_notes
          end

          def row_gaps
            frame = head + PARTITION_BELOW + 8.0
            exits = Exits.new(@columns, @boxes)
            RowGaps.new(@diagram, @ranking, exits, @metrics, frame).to_a
          end

          def header_height
            (@diagram.title ? TITLE_HEIGHT : 0) +
              (@diagram.warnings.size * WARNING_PITCH) +
              (@diagram.lanes.empty? ? 0 : HEADER_HEIGHT) +
              (@diagram.nodes.any?(&:partition) ? head : 0)
          end

          def place_columns(margin)
            keys = @columns.key.values.uniq.sort
            @bar_columns = BarColumns.new(@diagram, @ranking, @columns, @boxes)
            reach = reaches(keys)
            @centres = centres(keys, reach, margin)
            centre_nodes
            @bands = lane_bands(keys, reach)
          end

          def centre_nodes
            @diagram.nodes.each do |node|
              @boxes[node].cx = @centres[@columns.key[node]]
            end
          end

          def centres(keys, reach, margin)
            ColumnCentres.new(@columns, @boxes, reach, margin,
                              @bar_columns).call(keys)
          end

          # How far each column reaches left and right of its centre,
          # including notes and the labels hung on its arrows.
          def reaches(keys)
            reach = keys.to_h { |key| [key, [0.0, 0.0]] }
            @diagram.nodes.reject { |n| n.kind == :bar }.each do |node|
              key = @columns.key[node]
              reach[key] = widen(reach[key], node)
            end
            @bar_columns.widen(reach_labels(reach))
          end

          def widen(reach, node)
            half = @boxes[node].width / 2.0
            [[reach.first, half + note_room(node, :left)].max,
             [reach.last, half + note_room(node, :right)].max]
          end

          # A label sits to the right of the line it rides, and a bare
          # decision's question to the left of the line that enters it.
          def reach_labels(reach)
            @diagram.edges.each do |edge|
              next if edge.from.kind == :bar || edge.to.kind == :bar

              reach_text(reach, edge)
              reach_question(reach, edge.to) if edge.to.bare
            end
            reach
          end

          def reach_text(reach, edge)
            lines = edge.label.to_s.split("\n")
            return if lines.empty?

            side = reach[@columns.key[label_owner(edge)]]
            side[1] = [side[1], LABEL_OFFSET + width_of(lines)].max
          end

          def reach_question(reach, node)
            key = @columns.key[node]
            reach[key][0] = [reach[key][0],
                             BARE_LABEL_GAP + width_of(node.lines)].max
          end

          def width_of(lines)
            lines.empty? ? 0.0 : @metrics.text_width(lines, role: :arrow)
          end

          def label_owner(edge)
            edge.from.kind == :decision ? edge.to : edge.from
          end

          def note_room(node, side)
            widths = node.notes.select { |n| n.side == side }
              .map { |n| @metrics.note_box(n).width }
            widths.empty? ? 0.0 : widths.max + NOTE_GAP
          end

          def lane_bands(keys, reach)
            lanes = @diagram.lanes.each_with_index
            abut(lanes.filter_map do |(name, colour), idx|
              own = keys.select { |key| key.first == idx }
              band(name, colour, own, reach) unless own.empty?
            end)
          end

          # A decision centred on branches in the lane beside it reaches
          # over the border; the next lane starts where this one ends.
          def abut(bands)
            bands.each_cons(2) do |prior, band|
              band[:left] = [band[:left], prior[:right]].max
            end
          end

          def band(name, colour, own, reach)
            { name: name, colour: colour,
              left: @centres[own.first] - reach[own.first].first - BAND_PAD,
              right: @centres[own.last] + reach[own.last].last + BAND_PAD }
          end

          def place_rows
            heights = row_heights
            tops = heights.each_index.map { |row| row_top(heights, row) }
            @bottoms = tops.zip(heights).map(&:sum)
            @diagram.nodes.each { |node| centre_row(node, tops, heights) }
          end

          def centre_row(node, tops, heights)
            row = @ranking.rank[node]
            @boxes[node].cy = tops[row] + (heights[row] / 2.0)
          end

          def row_top(heights, row)
            @top + heights.first(row).sum + @gaps.first(row + 1).sum
          end

          def row_heights
            tall = @diagram.nodes.group_by { |node| @ranking.rank[node] }
            Array.new(tall.keys.max.to_i + 1) { |row| tallest(tall[row]) }
          end

          def tallest(nodes)
            nodes.to_a.map { |node| @boxes[node].height }.max.to_f
          end

          # A bar stretches over the boxes it fans out to or gathers.
          def fit_bars
            @diagram.nodes.select { |n| n.kind == :bar }.each do |bar|
              fan = @bar_columns.fan(bar).map { |n| @boxes[n] }
              stretch(@boxes[bar], fan) unless fan.empty?
            end
          end

          def stretch(box, fan)
            left, right = extent(fan)
            box.cx = (left + right) / 2.0
            box.width = [right - left, box.width].max
            hang(box, fan)
          end

          # The boxes the bar spans, and the middle of them where a lone
          # neighbour's arrow meets it.
          def hang(box, fan)
            box.fan = fan
            box.anchor = fan.map(&:cx).minmax.sum / 2.0
          end

          def extent(fan)
            [fan.map(&:left).min - BarColumns::OVERHANG,
             fan.map(&:right).max + BarColumns::OVERHANG]
          end

          def place_notes
            @notes = @diagram.nodes.to_h do |node|
              [node, node.notes.map { |note| [note, note_at(node, note)] }]
            end
          end

          def note_at(node, note)
            box = @metrics.note_box(note)
            anchor = @boxes[node]
            box.cy = anchor.cy
            box.cx = note_centre(box, anchor, note.side)
            box
          end

          def note_centre(box, anchor, side)
            if side == :right
              anchor.right + NOTE_GAP + (box.width / 2.0)
            else
              anchor.left - NOTE_GAP - (box.width / 2.0)
            end
          end
        end
      end
    end
  end
end
