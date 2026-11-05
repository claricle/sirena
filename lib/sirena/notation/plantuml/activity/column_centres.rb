# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Activity
        # Where each column's centre falls. Columns stand left to right,
        # each as wide as what reaches out of it. A decision's own column is
        # a trunk: it takes no room and hangs midway between its first and
        # last branch, and those branches stand a hexagon's width and a gap
        # apart at least.
        class ColumnCentres
          COLUMN_GAP = 20.0
          LANE_GAP = 30.0
          # What a label's far end adds to the block a wide decision centres on.
          LABEL_PAD = 3.5

          # @param reach [Hash{Array => Array(Float, Float)}] how far each
          #   column reaches left and right of its centre
          def initialize(columns, boxes, reach, margin, bars)
            @columns = columns
            @boxes = boxes
            @reach = reach
            @margin = margin
            @bars = bars
            @trunks = columns.spans.keys.group_by { |node| columns.key[node] }
          end

          # @param keys [Array<Array>] every column key, in order
          # @return [Hash{Array => Float}]
          def call(keys)
            placed = settle(keys - @trunks.keys)
            keys.to_h { |key| [key, placed[key] || trunk_centre(key, placed)] }
          end

          private

          # Spreads the solid columns, moving some right until every
          # decision's branches stand far enough apart.
          def settle(solid)
            extra = Hash.new(0.0)
            placed = spread(solid, extra)
            (solid.size * 2).times do
              deficit = branch_deficit(placed, solid) or break
              extra[deficit.first] += deficit.last
              placed = spread(solid, extra)
            end
            placed
          end

          def spread(solid, extra)
            cursor = @margin
            solid.each_with_index.to_h do |key, index|
              cursor += gap(solid[index - 1], key, extra) if index.positive?
              centre = cursor + @reach[key].first
              cursor = centre + @reach[key].last
              [key, centre]
            end
          end

          def gap(previous, key, extra)
            COLUMN_GAP + (previous.first == key.first ? 0 : LANE_GAP) +
              extra[key]
          end

          # The first column that has to move right so that some decision's
          # branches stand apart, and by how much.
          def branch_deficit(placed, solid)
            @columns.spans.each do |node, (first, last)|
              short = shortfall(node, first, last, placed)
              edge = (@bars.fan_keys(first) || [@columns.key[first]]).max
              anchor = solid.find { |key| (key <=> edge).positive? }
              return [anchor, short] if short.positive? && anchor
            end
            nil
          end

          def shortfall(node, left, right, placed)
            @boxes[node].width + COLUMN_GAP -
              (head_centre(right, placed) - head_centre(left, placed))
          end

          def centre(key, placed, seen = [])
            placed.fetch(key) { trunk_centre(key, placed, seen) }
          end

          # Where the arrow into a branch lands: a bar takes it midway
          # between the branches it fans out to.
          def head_centre(node, placed, seen = [])
            keys = @bars.fan_keys(node)
            return centre(@columns.key[node], placed, seen) unless keys

            keys.map { |key| centre(key, placed, seen) }.minmax.sum / 2.0
          end

          def trunk_centre(key, placed, seen = [])
            return 0.0 if seen.include?(key)

            seen += [key]
            mids = @trunks.fetch(key).map { |node| mid(node, placed, seen) }
            mids.sum / mids.size
          end

          def mid(node, placed, seen)
            first, last = @columns.spans[node]
            left = head_centre(first, placed, seen)
            right = head_centre(last, placed, seen)
            return (left + right) / 2.0 unless @columns.wide?(node)

            block(first, last, [left, right]).sum / 2.0
          end

          # The edges of the steps a wide decision's branches stand in, the
          # outer labels' width counted.
          def block(first, last, heads)
            [heads.first - @reach[@columns.key[first]].first,
             heads.last + @reach[@columns.key[last]].last + LABEL_PAD]
          end
        end
      end
    end
  end
end
