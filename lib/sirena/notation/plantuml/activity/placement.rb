# frozen_string_literal: true

require_relative "metrics"

module Sirena
  module Notation
    module PlantUML
      module Activity
        # Puts every node's box at its row and column, then fits each bar to
        # the nodes it joins and each note beside its node.
        class Placement
          RANK_GAP = 40.0
          COLUMN_GAP = 44.0
          LANE_GAP = 30.0
          NOTE_GAP = 10.0
          TITLE_HEIGHT = 26.0
          HEADER_HEIGHT = 28.0
          PARTITION_PAD = 22.0
          BAR_OVERHANG = 14.0
          BAND_PAD = 14.0

          # @return [Hash{Node => Box}]
          attr_reader :boxes
          # @return [Array<Float>] the bottom of each row
          attr_reader :bottoms
          # @return [Hash{Node => Array<Array(Note, Box)>}]
          attr_reader :notes
          # @return [Float] the top of the first row
          attr_reader :top
          # @return [Array<Hash>] a name, colour, left and right per lane
          attr_reader :bands

          def initialize(diagram, ranking, columns, margin)
            @diagram = diagram
            @ranking = ranking
            @columns = columns
            @boxes = diagram.nodes.to_h { |n| [n, Metrics.box_for(n)] }
            @top = margin + header_height
            place_columns(margin)
            place_rows
            fit_bars
            place_notes
          end

          private

          def header_height
            (@diagram.title ? TITLE_HEIGHT : 0) +
              (@diagram.lanes.empty? ? 0 : HEADER_HEIGHT) +
              (@diagram.nodes.any?(&:partition) ? PARTITION_PAD : 0)
          end

          def place_columns(margin)
            keys = @columns.key.values.uniq.sort
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
            cursor = margin
            keys.each_with_index.to_h do |key, index|
              cursor += spacing(keys[index - 1], key) if index.positive?
              centre = cursor + reach[key].first
              cursor = centre + reach[key].last
              [key, centre]
            end
          end

          def spacing(previous, key)
            COLUMN_GAP + (previous.first == key.first ? 0 : LANE_GAP)
          end

          # How far each column reaches left and right of its centre,
          # including notes.
          def reaches(keys)
            reach = keys.to_h { |key| [key, [0.0, 0.0]] }
            @diagram.nodes.reject { |n| n.kind == :bar }.each do |node|
              key = @columns.key[node]
              reach[key] = widen(reach[key], node)
            end
            reach
          end

          def widen(reach, node)
            half = @boxes[node].width / 2.0
            [[reach.first, half + note_room(node, :left)].max,
             [reach.last, half + note_room(node, :right)].max]
          end

          def note_room(node, side)
            widths = node.notes.select { |n| n.side == side }
              .map { |n| Metrics.note_box(n).width }
            widths.empty? ? 0.0 : widths.max + NOTE_GAP
          end

          def lane_bands(keys, reach)
            @diagram.lanes.each_with_index.filter_map do |(name, colour), idx|
              own = keys.select { |key| key.first == idx }
              band(name, colour, own, reach) unless own.empty?
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
            @top + heights.first(row).sum + (row * RANK_GAP)
          end

          def row_heights
            tall = @diagram.nodes.group_by { |node| @ranking.rank[node] }
            Array.new(tall.keys.max.to_i + 1) { |row| tallest(tall[row]) }
          end

          def tallest(nodes)
            nodes.to_a.map { |node| @boxes[node].height }.max.to_f
          end

          # A bar stretches over the nodes on either side of it.
          def fit_bars
            @diagram.nodes.select { |n| n.kind == :bar }.each do |bar|
              xs = neighbours(bar).map { |n| @boxes[n].cx }
              stretch(@boxes[bar], xs.minmax) unless xs.empty?
            end
          end

          def stretch(box, span)
            box.cx = span.sum / 2.0
            box.width = [span.last - span.first + (2 * BAR_OVERHANG),
                         box.width].max
          end

          def neighbours(bar)
            @diagram.edges.filter_map do |edge|
              other = if edge.from.equal?(bar)
                        edge.to
                      elsif edge.to.equal?(bar)
                        edge.from
                      end
              other if other && other.kind != :bar
            end
          end

          def place_notes
            @notes = @diagram.nodes.to_h do |node|
              [node, node.notes.map { |note| [note, note_at(node, note)] }]
            end
          end

          def note_at(node, note)
            box = Metrics.note_box(note)
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
