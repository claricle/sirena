# frozen_string_literal: true

require_relative "axis_solver"
require_relative "routes"

module Sirena
  module Notation
    module PlantUML
      module State
        # Where graphviz puts the rows of one container along the x axis. It
        # ranks the states, gives every transition a node at each rank it
        # crosses, a label being the node at its middle, then places those
        # nodes so the transitions run as straight as they can. A layout
        # that sees only the states puts them elsewhere once the labels of a
        # rank need more room than its states.
        #
        # A row holding a composite or a lone start marker keeps its place;
        # the others move to the x {AxisSolver} gives them. Ranks are read
        # from where the rows stand, so the y of a state never changes.
        class DotAxis
          # The room graphviz keeps between two nodes of a rank.
          NODESEP = 35.0
          # The width of the node a transition has at a rank it only crosses.
          CROSSING = 6.0
          # How far apart the centres of two states of one rank can be.
          BAND = 4.0
          # How near a cluster's border a transition may meet it.
          MARGIN = 16.0
          # What a segment of a transition weighs, by whether both of its
          # ends are nodes the transition has at a rank it crosses.
          END_WEIGHT = 2
          CROSSING_WEIGHT = 8
          private_constant :NODESEP, :CROSSING, :BAND, :MARGIN, :END_WEIGHT,
                           :CROSSING_WEIGHT

          # One end of a segment of a transition: an item, the distance of
          # the joint from its centre, and whether it is a crossing.
          Joint = Struct.new(:item, :offset, :crossing)
          private_constant :Joint

          # @param edges [Array<Hash>] every transition of the graph
          # @param nodes [Hash{String=>Hash}] every state by id
          # @param parent [Hash{String=>String}] the container of each state
          def initialize(edges, nodes, parent)
            @edges = edges
            @nodes = nodes
            @parent = parent
          end

          # Slides the rows to their place.
          #
          # @param rows [Array<Row>] the container's rows, placed
          # @return [Array<Row>] the rows that moved
          def apply(rows)
            return [] unless rows.any? { |row| composite?(row) }

            prepare(rows)
            solve(@edges.flat_map { |edge| segments(edge) }, rows)
            moved = rows.reject { |row| shift_of(row).zero? }
            moved.each { |row| row.slide(shift_of(row)) }
          end

          private

          def prepare(rows)
            @home = home_of(rows)
            @bands = bands_of(rows)
            @items = rows.to_h { |row| [row.id, items_of(row)] }
            @entries = rows.select { |row| composite?(row) }
              .to_h { |row| [row.id, entry_of(row)] }
          end

          def home_of(rows)
            rows.flat_map { |row| row.nodes.map { |node| [node[:id], row] } }
              .to_h
          end

          def solve(links, rows)
            items = @items.values.flat_map(&:values) + @entries.values +
              links.flat_map { |link| [link.from, link.to] }
            AxisSolver.new(items.uniq, links, gap: NODESEP,
                                              floor: rows.map(&:left).min,
                                              chain_weight: CROSSING_WEIGHT)
              .solve
          end

          def shift_of(row)
            (@items.fetch(row.id).values.first.x - centre_of(row)).round(3)
          end

          def centre_of(row)
            row.left + (row.width / 2.0)
          end

          def composite?(row)
            row.nodes.any? { |node| Array(node[:children]).any? }
          end

          def anchored?(row)
            composite?(row) ||
              row.nodes.all? do |node|
                node.dig(:metadata, :state_type) == "start"
              end
          end

          # The items of a row by rank: one for a row that moves, one for
          # each rank a composite spans.
          def items_of(row)
            bands = row.nodes.flat_map { |node| leaf_centres(node, 0.0) }
              .map { |centre| band_of(centre) }
            ((2 * bands.min)..(2 * bands.max)).to_h do |rank|
              [rank, item(row, rank)]
            end
          end

          def item(row, rank)
            AxisSolver::Item.new(rank: rank, width: row.width,
                                 x: centre_of(row), fixed: anchored?(row))
          end

          # Where a transition meets a cluster: a point on its top rank that
          # graphviz places like any node, within the cluster's border.
          def entry_of(row)
            AxisSolver::Item.new(
              rank: @items.fetch(row.id).keys.min, width: 0.0,
              x: centre_of(row), fixed: false, track: :entry,
              low: row.left + MARGIN, high: row.left + row.width - MARGIN
            )
          end

          # The y of the centre of each state a node holds, or of the node
          # itself when it holds none.
          def leaf_centres(node, top)
            y = top + node[:y]
            return [y + (node[:height] / 2.0)] if Array(node[:children]).empty?

            node[:children].flat_map { |child| leaf_centres(child, y) }
          end

          # The distinct rows of states, top down: states whose centres are
          # a few points apart share one.
          def bands_of(rows)
            centres = rows.flat_map(&:nodes).flat_map do |node|
              leaf_centres(node, 0.0)
            end
            centres.sort.chunk_while { |one, two| two - one <= BAND }
              .map(&:first)
          end

          def band_of(centre)
            @bands.rindex { |band| band <= centre + BAND }
          end

          # The links of the chain of nodes a transition makes between the
          # ranks of its two ends, the upper one first.
          def segments(edge)
            return [] unless Routes.level_pair(edge, @parent, @home.keys)

            upper, lower = ends(edge)
            return [] if upper.item.rank == lower.item.rank

            [upper, *crossings(edge, upper, lower), lower].each_cons(2)
              .map { |one, two| link(one, two) }
          end

          def ends(edge)
            [joint(edge[:sources].first), joint(edge[:targets].first)]
              .sort_by { |end_| end_.item.rank }
          end

          def link(one, two)
            weight = one.crossing && two.crossing ? CROSSING_WEIGHT : END_WEIGHT
            AxisSolver::Link.new(from: one.item, to: two.item,
                                 from_offset: one.offset, to_offset: two.offset,
                                 weight: weight)
          end

          def crossings(edge, upper, lower)
            first = upper.item.rank
            last = lower.item.rank
            ((first + 1)...last).map do |rank|
              width = rank == (first + last) / 2 ? label_width(edge) : CROSSING
              crossing(width, rank, upper, lower)
            end
          end

          def crossing(width, rank, upper, lower)
            item = AxisSolver::Item.new(
              rank: rank, width: width, x: along(rank, upper, lower),
              fixed: false
            )
            Joint.new(item, 0.0, true)
          end

          # Where the straight line between two joints crosses a rank.
          def along(rank, upper, lower)
            top = upper.item.rank
            by = (rank - top).fdiv(lower.item.rank - top)
            spot(upper) + ((spot(lower) - spot(upper)) * by)
          end

          def label_width(edge)
            label = Array(edge[:labels]).first
            label ? label[:width] : CROSSING
          end

          def spot(joint)
            joint.item.x + joint.offset
          end

          def joint(id)
            member = Routes.member_of(id, @parent, @home.keys)
            row = @home.fetch(member)
            return Joint.new(@entries.fetch(row.id), 0.0, false) if
              entered?(id, member)

            Joint.new(item_of(row, id, member),
                      level_at(id, member, :x, :width) - centre_of(row), false)
          end

          # A transition to or from a composite itself meets its cluster at
          # the entry, not at the cluster's box.
          def entered?(id, member)
            id == member && Array(@nodes[id][:children]).any?
          end

          # The item of a row at the rank of a state it holds.
          def item_of(row, id, member)
            items = @items.fetch(row.id)
            centre = level_at(id, member, :y, :height)
            items.fetch((2 * band_of(centre)).clamp(*items.keys.minmax))
          end

          # The centre of a state along an axis, in the coordinates of the
          # container its row stands in.
          def level_at(id, member, axis, size)
            at = @nodes[id][axis] + (@nodes[id][size] / 2.0)
            until id == member
              id = @parent[id]
              at += @nodes[id][axis]
            end
            at
          end
        end
      end
    end
  end
end
