# frozen_string_literal: true

require_relative "../../../layout/elk_placement"
require_relative "routes"

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
          NOTE_GAP = 30.0
          private_constant :MARGIN, :PAD, :HEADER, :NOTE_GAP

          # @param graph [Hash] the graph from the state layout's build_graph
          def initialize(graph)
            @graph = graph
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

            elk = lay_out(members)
            spots = elk[:children].to_h { |placed| [placed[:id], placed] }
            members.each { |node| spot(node, spots.fetch(node[:id])) }
            elk
          end

          def lay_out(members)
            elk = {
              id: "level", layoutOptions: @options,
              children: members.map { |node| unit_of(node) },
              edges: level_edges(members)
            }
            ::Sirena::Layout::ElkPlacement.apply(elk)
          end

          # A node and the note beside it are laid out as one box.
          def unit_of(node)
            note = @notes[node[:id]]
            return node.slice(:id, :width, :height) unless note

            { id: node[:id], width: node[:width] + note[:width] + NOTE_GAP,
              height: [node[:height], note[:height]].max }
          end

          def level_edges(members)
            ids = members.map { |node| node[:id] }
            @graph[:edges].filter_map do |edge|
              pair = Routes.level_pair(edge, @parent, ids)
              next unless pair

              { id: edge.object_id.to_s, sources: [pair.first],
                targets: [pair.last] }
            end
          end

          def spot(node, placed)
            node[:x] = placed[:x]
            node[:y] = placed[:y]
            note = @notes[node[:id]]
            place_note(node, note) if note
          end

          # The unit's box holds the target and its note side by side.
          def place_note(node, note)
            left = note.dig(:metadata, :note_position) == "left"
            unit_x = node[:x]
            note[:x] = left ? unit_x : unit_x + node[:width] + NOTE_GAP
            node[:x] = unit_x + note[:width] + NOTE_GAP if left
            center_note(node, note)
          end

          def center_note(node, note)
            note[:y] = node[:y] + ((node[:height] - note[:height]) / 2.0)
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
