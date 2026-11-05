# frozen_string_literal: true

require_relative "../../../layout/elk_placement"
require_relative "routes"
require_relative "ranking"
require_relative "level_edges"
require_relative "row"
require_relative "rows"

module Sirena
  module Notation
    module PlantUML
      module State
        # Places the states of an ELK-shaped state graph one container at a
        # time, innermost first. A composite is sized from what it holds, a
        # header for its name above the children, so a child never sits on
        # its parent's title and a parent is never smaller than its content.
        #
        # Every position written is relative to the container, as the layout
        # scene expects. Edges are written as absolute `:sections`, routed by
        # {Routes}. A note sits beside its target and travels with it.
        class Hierarchy
          MARGIN = 20.0
          PAD = 24.0
          HEADER = 36.0
          # The step of one rank between the tops of two composites, as
          # PlantUML measures it: a start marker and the gap after it.
          RANK_DROP = 68.0
          private_constant :MARGIN, :PAD, :RANK_DROP

          # @param graph [Hash] the graph from the state layout's build_graph
          # @param flat [Array<Array(String, String)>] the transitions drawn
          #   on one rank
          def initialize(graph, flat = [])
            @graph = graph
            @flat = flat
            @options = graph[:layoutOptions]
            @nodes = {}
            @parent = {}
            @levels = {}
            @notes = {}
          end

          # Places the graph's states and edges in place.
          def place
            index(@graph[:children], nil)
            adopt_notes
            ranking = Ranking.new(@graph[:children], @graph[:edges])
            @level_edges = LevelEdges.new(@graph[:edges], @parent, ranking)
            place_level(nil, @graph[:children])
            Routes.new(@graph, @nodes, @parent, @levels).write
          end

          private

          def index(children, parent)
            children.each do |node|
              @nodes[node[:id]] = node
              @parent[node[:id]] = parent
              index(node[:children] || [], node[:id])
            end
          end

          # A note moves into the container of its target.
          def adopt_notes
            @graph[:children].select { |node| note?(node) }.each do |note|
              target = note.dig(:metadata, :note_target)
              move_note(note, target) if @nodes.key?(target)
            end
          end

          def move_note(note, target)
            holder = @parent[target]
            @graph[:children].delete(note)
            @parent[note[:id]] = holder
            (holder ? @nodes[holder][:children] : @graph[:children]) << note
            @notes[target] = note
          end

          def note?(node)
            node.dig(:metadata, :state_type) == "note"
          end

          def members_of(children)
            children.reject { |child| @notes.value?(child) }
          end

          def place_level(owner, children)
            children.each do |child|
              if child[:children]&.any?
                place_level(child[:id],
                            child[:children])
              end
            end
            elk = position(members_of(children))
            shift = shift_for(owner, children)
            finish(owner, children, shift)
            @levels[owner] = { elk: elk, shift: shift }
          end

          # @return [Hash, nil] the placed ELK graph of the members
          def position(members)
            return if members.empty?

            rows = rows_of(members)
            elk = lay_out(rows)
            settle(rows, elk)
            elk
          end

          def settle(rows, elk)
            spots = elk[:children].to_h { |placed| [placed[:id], placed] }
            drop = entered_peers(rows)
            rows.each do |row|
              spot(row, spots.fetch(row.id), drop.include?(row.id))
            end
            follow(elk, drop)
          end

          # A route ELK drew to a row that has moved follows it down: its
          # end and last bend travel with the row.
          def follow(elk, moved)
            elk[:edges].each do |edge|
              next unless edge[:targets].intersect?(moved)

              (edge[:sections] || []).each { |section| lower(section) }
            end
          end

          def lower(section)
            [section[:endPoint], section[:bendPoints]&.last].compact
              .each { |point| point[:y] += RANK_DROP }
          end

          # Composites side by side, the one a start marker enters stands a
          # rank below the others, as PlantUML ranks the cycle between them
          # from the entry.
          def entered_peers(rows)
            peers = @level_edges.peer_ids(rows)
            entered = peers.select { |id| entered_by_start?(id) }
            entered.size == peers.size ? [] : entered
          end

          def entered_by_start?(id)
            @graph[:edges].any? do |edge|
              edge[:targets].first == id &&
                @nodes[edge[:sources].first]&.dig(:metadata, :state_type) ==
                  "start"
            end
          end

          def lay_out(rows)
            elk = {
              id: "level", layoutOptions: @options,
              children: rows.map { |row| unit_of(row) },
              edges: @level_edges.of(rows)
            }
            ::Sirena::Layout::ElkPlacement.apply(elk)
          end

          # The members of a level, those joined by a flat transition
          # gathered into one row in the order they chain.
          def rows_of(members)
            by_id = members.to_h { |node| [node[:id], node] }
            rows = Rows.new(@flat).chains(by_id.keys).map do |ids|
              Row.new(by_id.values_at(*ids), @notes)
            end
            reversed_peers(rows)
          end

          # Composites side by side that a transition joins stand in the
          # reverse of the order they are listed, as PlantUML draws them.
          def reversed_peers(rows)
            peers = @level_edges.peer_ids(rows)
            spots = rows.each_index.select { |at| peers.include?(rows[at].id) }
            order = spots.zip(spots.reverse).to_h
            rows.each_index.map { |at| rows[order.fetch(at, at)] }
          end

          def unit_of(row)
            { id: row.id, width: row.width, height: row.height }
          end

          def spot(row, placed, dropped)
            row.place(placed[:x], placed[:y] + (dropped ? RANK_DROP : 0))
          end

          def shift_for(owner, children)
            return [MARGIN, MARGIN] unless owner

            left = children.map { |child| child[:x] }.min || 0
            top = children.map { |child| child[:y] }.min || 0
            [PAD - left, HEADER - top]
          end

          def finish(owner, children, shift)
            children.each do |child|
              child[:x] += shift.first
              child[:y] += shift.last
            end
            size_container(@nodes[owner], children) if owner
          end

          def size_container(node, children)
            title = node[:labels].first&.fetch(:width, 0) || 0
            node[:width] = [extent(children, :x, :width) + PAD,
                            title + (2 * PAD)].max
            node[:height] = extent(children, :y, :height) + PAD
          end

          def extent(children, origin, size)
            children.map { |child| child[origin] + child[size] }.max || 0
          end
        end
      end
    end
  end
end
