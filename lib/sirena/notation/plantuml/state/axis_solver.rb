# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module State
        # Assigns the x of the items of a layered graph the way graphviz does:
        # it minimises the summed, weighted horizontal length of the links
        # while keeping the items of a rank apart by their widths and a gap.
        # The order of a rank is the order of the items' starting x.
        #
        # The minimum is approached without a network simplex: the items
        # first relax toward the mean of what they are linked to, then a
        # group of items at a time moves to the weighted median of the links
        # that leave it, until no move shortens the links.
        class AxisSolver
          # An item at a rank, `x` being its centre. A fixed item never
          # moves; the others keep within `low` and `high`. An item stands
          # apart only from the items of its own `track`.
          Item = Struct.new(:rank, :width, :x, :fixed, :low, :high, :track,
                            keyword_init: true) do
            # Two items are the same only when they are one item, however
            # alike, and moving one must not change which it is.
            def ==(other)
              equal?(other)
            end
            alias_method :eql?, :==

            def hash
              object_id.hash
            end
          end

          # A link from `from` to `to`, each joined at an offset from its
          # item's centre.
          Link = Struct.new(:from, :to, :from_offset, :to_offset, :weight,
                            keyword_init: true) do
            def from_at
              from.x + from_offset
            end

            def to_at
              to.x + to_offset
            end
          end

          SWEEPS = 100
          WARMUP = 30
          EPSILON = 1e-6
          private_constant :SWEEPS, :WARMUP, :EPSILON

          # @param items [Array<Item>] with their starting x
          # @param links [Array<Link>]
          # @param gap [Float] the room between two items of a rank
          # @param floor [Float] the left edge no item may cross
          # @param chain_weight [Integer, nil] the weight of the links that
          #   join the nodes of one long transition, which move together
          def initialize(items, links, gap:, floor:, chain_weight: nil)
            @gap = gap
            @floor = floor
            @chain_weight = chain_weight
            @ranks = items.group_by { |item| [item.rank, item.track] }.values
              .map { |found| found.sort_by(&:x) }
            @row_of = rows_by_item
            @links = links_by_item(links)
          end

          # Moves the items in place.
          def solve
            @ranks.each { |row| clear(row) }
            WARMUP.times { relax }
            SWEEPS.times { break unless improved? }
          end

          private

          def rows_by_item
            @ranks.each_with_object({}.compare_by_identity) do |row, found|
              row.each { |item| found[item] = row }
            end
          end

          def links_by_item(links)
            links.flat_map { |link| [[link.from, link], [link.to, link]] }
              .each_with_object({}.compare_by_identity) do |(item, link), found|
                (found[item] ||= []) << link
              end
          end

          def relax
            @ranks.each do |row|
              row.each { |item| put(item, mean_pull(item)) if linked?(item) }
              clear(row)
            end
          end

          def linked?(item)
            @links.key?(item)
          end

          def mean_pull(item)
            pulls = @links.fetch(item).map { |link| pull(item, link) }
            pulls.sum { |at, weight| at * weight } / pulls.sum(&:last)
          end

          def pull(item, link)
            at = if link.from.equal?(item)
                   link.to_at - link.from_offset
                 else
                   link.from_at - link.to_offset
                 end
            [at, link.weight]
          end

          # Pushes the items of a rank apart, the fixed ones staying put.
          def clear(row)
            row.each_cons(2) { |left, right| push_right(left, right) }
            row.reverse.each_cons(2) { |right, left| push_left(left, right) }
          end

          def push_right(left, right)
            put(right, [right.x, left.x + room(left, right)].max)
          end

          def push_left(left, right)
            put(left, [left.x, right.x - room(left, right)].min)
          end

          def put(item, at)
            item.x = at.clamp(*bounds(item)) unless item.fixed
          end

          def bounds(item)
            low = item.low || (@floor + (item.width / 2.0))
            [low, [item.high || Float::INFINITY, low].max]
          end

          def room(left, right)
            ((left.width + right.width) / 2.0) + @gap
          end

          def improved?
            @ranks.flatten.map { |item| improves?(item) }.any?
          end

          def improves?(item)
            seeds(item).product(%i[right left]).map do |seed, side|
              slides?(seed, side)
            end.any?
          end

          # The sets of items that may move together from `item`: itself,
          # and the whole chain of nodes a long transition has.
          def seeds(item)
            [[item], chain(item)].uniq
          end

          def chain(item)
            found = [item]
            found.each do |one|
              tied(one).each do |other|
                found << other unless found.include?(other)
              end
            end
            found
          end

          def tied(item)
            @links.fetch(item, []).select do |link|
              link.weight == @chain_weight
            end
              .flat_map { |link| [link.from, link.to] }
          end

          def slides?(seed, side)
            group = pushed(seed, side)
            return false if group.any?(&:fixed)

            links = crossing(group)
            shift = best_shift(links).clamp(*slack(group))
            return false unless gain(links, shift).positive?

            group.each { |item| item.x += shift }
            true
          end

          # The seed and, toward `side`, the items it touches in a chain.
          def pushed(seed, side)
            seed.dup.tap do |group|
              group.each do |item|
                near = neighbour(item, side)
                group << near if pushes?(item, near, group)
              end
            end
          end

          def pushes?(item, near, group)
            near && touching?(item, near) && !group.include?(near)
          end

          def neighbour(item, side)
            row = @row_of.fetch(item)
            at = row.index(item) + (side == :right ? 1 : -1)
            row[at] unless at.negative?
          end

          def touching?(near, far)
            ((near.x - far.x).abs - room(near, far)).abs < EPSILON
          end

          # How far the group may move left (negative) and right.
          def slack(group)
            lows = group.map { |item| left_reach(item, group) }
            highs = group.map { |item| right_reach(item, group) }
            [[lows.max, 0.0].min, [highs.min, 0.0].max]
          end

          def left_reach(item, group)
            near = neighbour(item, :left)
            own = bounds(item).first - item.x
            return own if near.nil? || group.include?(near)

            [own, near.x + room(near, item) - item.x].max
          end

          def right_reach(item, group)
            near = neighbour(item, :right)
            own = bounds(item).last - item.x
            return own if near.nil? || group.include?(near)

            [own, near.x - room(item, near) - item.x].min
          end

          # Each link that leaves the group as [distance from the group to
          # its far end, weight].
          def crossing(group)
            group.flat_map do |item|
              @links.fetch(item, [])
            end.uniq.filter_map do |link|
              from = group.include?(link.from)
              next if from == group.include?(link.to)

              [length(link, from), link.weight]
            end
          end

          def length(link, from_inside)
            span = link.to_at - link.from_at
            from_inside ? span : -span
          end

          def best_shift(links)
            return 0.0 if links.empty?

            seen = 0.0
            links.sort_by(&:first).find do |_, weight|
              (seen += weight) * 2 >= links.sum(&:last)
            end.first
          end

          def gain(links, shift)
            cost(links, 0.0) - cost(links, shift)
          end

          def cost(links, shift)
            links.sum { |gap, weight| weight * (gap - shift).abs }
          end
        end
      end
    end
  end
end
