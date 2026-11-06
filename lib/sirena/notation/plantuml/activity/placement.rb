# frozen_string_literal: true

require_relative "bar_columns"
require_relative "column_centres"
require_relative "exits"
require_relative "metrics"
require_relative "reach"
require_relative "lane_steps"
require_relative "lane_titles"
require_relative "legacy_row_gaps"
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
          # The size the JAR draws a swimlane's title at, and the room it
          # keeps about the title inside the band.
          LANE_TITLE = 18
          LANE_TITLE_PAD = 10.0
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
            return LegacyRowGaps.new(@diagram, @ranking, @metrics).to_a if
              @diagram.legacy

            frame = head + PARTITION_BELOW + 8.0
            RowGaps.new(@diagram, @ranking, exits, @metrics, frame).to_a
          end

          def exits
            @exits ||= Exits.new(@columns, @boxes)
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
            centre_columns(keys, reach, margin)
            centre_nodes
            @bands = lane_bands(keys, reach.columns)
          end

          # Centres the columns; a lane whose title is wider than its band
          # widens the band, and the columns are centred again.
          def centre_columns(keys, reach, margin)
            @centres = centres(keys, reach, margin)
            bands = lane_bands(keys, reach.columns)
            return unless lane_titles.widen(bands, reach).positive?

            @centres = centres(keys, reach, margin)
          end

          def lane_titles
            LaneTitles.new(@metrics, LANE_TITLE, LANE_TITLE_PAD)
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
            reach = Reach.new(keys, by_row: @diagram.legacy)
            @diagram.nodes.reject { |n| n.kind == :bar }.each do |node|
              widen(reach, node)
            end
            reach_lines(reach)
            @bar_columns.widen(reach_labels(reach))
            reach
          end

          def widen(reach, node)
            half = @boxes[node].width / 2.0
            grow(reach, node, 0, half + note_room(node, :left))
            grow(reach, node, 1, half + note_room(node, :right))
          end

          def grow(reach, node, side, value)
            reach.grow(@columns.key[node], @ranking.row(node), side, value)
          end

          # An arrow that runs past rows stands on them as a line, in its
          # own column and where it lands, as wide as nothing; one that
          # runs back up the page passes none.
          def reach_lines(reach)
            return unless @diagram.legacy

            @diagram.edges.each { |edge| reach_line(reach, edge) }
          end

          def reach_line(reach, edge)
            rows = ((@ranking.rank[edge.from] + 1)...@ranking.rank[edge.to])
            [edge.from, edge.to].each do |node|
              reach.line(@columns.key[node], rows)
            end
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

            grow(reach, label_owner(edge), 1, LABEL_OFFSET + width_of(lines))
          end

          def reach_question(reach, node)
            grow(reach, node, 0, BARE_LABEL_GAP + width_of(node.lines))
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
            { name: name, colour: colour, columns: own,
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
            @boxes[node].cy = tops[row] + offset(node, row, heights)
            hang_lane(node, tops)
          end

          # A lane's first step hangs from the top of its row and its last
          # stands just over the diamond that closes the branches, wherever
          # the rows would have put them.
          def hang_lane(node, tops)
            box = @boxes[node]
            centre = lane_steps.centre(node, box.height, tops)
            box.cy = centre if centre
          end

          def lane_steps
            @lane_steps ||= LaneSteps.new(@diagram, @ranking, exits)
          end

          # A parked node sits in the gap under its row, a node on a row
          # in the middle of it.
          def offset(node, row, heights)
            return heights[row] / 2.0 unless @ranking.parked?(node)

            heights[row] + (@gaps[row + 1] / 2.0)
          end

          def row_top(heights, row)
            @top + heights.first(row).sum + @gaps.first(row + 1).sum
          end

          def row_heights
            tall = @diagram.nodes.reject { |node| parked_or_hung?(node) }
              .group_by { |node| @ranking.rank[node] }
            Array.new(tall.keys.max.to_i + 1) { |row| tallest(tall[row]) }
          end

          def parked_or_hung?(node)
            @ranking.parked?(node) || lane_steps.hung?(node)
          end

          def tallest(nodes)
            nodes.to_a.map { |node| @boxes[node].height }.max.to_f
          end

          # A bar stretches over the boxes it fans out to or gathers.
          def fit_bars
            @diagram.nodes.select { |n| n.kind == :bar }.each do |bar|
              fan = @bar_columns.fan(bar).map { |n| @boxes[n] }
              stretch(bar, fan) unless fan.empty?
            end
          end

          def stretch(bar, fan)
            box = @boxes[bar]
            left, right = extent(fan)
            box.cx = (left + right) / 2.0
            box.width = [right - left, box.width].max unless bar.legacy
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
