# frozen_string_literal: true

require_relative "route_geometry"

module Sirena
  module Notation
    module PlantUML
      module State
        # Writes each transition of a placed state graph as absolute
        # `:sections` plus the point its label sits at.
        #
        # A transition between two boxes of one container keeps the route ELK
        # gave it. Every other one (a loop, one that crosses a container's
        # border, one beside a note, one ELK dropped to break a cycle) is a
        # straight line between the two states' borders. Transitions between
        # the same two states are spread apart so none hides another.
        class Routes
          include RouteGeometry

          # @return [Array(String, String), nil] the two members of a
          #   container the edge joins, nil when it does not join two of them
          def self.level_pair(edge, parent, ids)
            source = member_of(edge[:sources].first, parent, ids)
            target = member_of(edge[:targets].first, parent, ids)
            [source, target] if source && target && source != target
          end

          def self.member_of(id, parent, ids)
            id = parent[id] until id.nil? || ids.include?(id)
            id
          end

          def initialize(graph, nodes, parent, levels)
            @graph = graph
            @nodes = nodes
            @parent = parent
            @levels = levels
            @boxes = {}
          end

          def write
            measure(@graph[:children], 0.0, 0.0)
            routed = @graph[:edges].map { |edge| [edge, polyline(edge)] }
            spread(routed).each do |edge, points, slot|
              record(edge, points, slot)
            end
          end

          private

          def record(edge, points, slot)
            edge[:sections] = [section(points)]
            edge[:label_at] = label_point(points, edge[:labels]&.first, slot)
          end

          def measure(children, left, top)
            children.each do |node|
              box = Box.new(left + node[:x], top + node[:y],
                            node[:width], node[:height], node)
              @boxes[node[:id]] = box
              measure(node[:children] || [], box.x, box.y)
            end
          end

          def polyline(edge)
            source = edge[:sources].first
            target = edge[:targets].first
            return loop_points(@boxes.fetch(source)) if source == target

            elk_route(edge, source, target) || straight(source, target)
          end

          def elk_route(edge, source, target)
            owner, level = @levels.find { |_, found| placed_edge(found, edge) }
            placed = level && placed_edge(level, edge)
            return unless placed && direct?(placed, source, target)

            origin = owner ? @boxes.fetch(owner) : Box.new(0.0, 0.0, 0, 0, nil)
            shifted(placed[:sections].first, origin, level[:shift])
          end

          def placed_edge(level, edge)
            level[:elk]&.fetch(:edges)&.find do |found|
              found[:id] == edge.object_id.to_s && found[:sections]&.any?
            end
          end

          # The ELK route joins the two boxes of the container; it is the
          # edge's own route only when those are the two states themselves
          # and neither carries a note.
          def direct?(placed, source, target)
            placed[:sources] == [source] && placed[:targets] == [target] &&
              !noted?(source) && !noted?(target)
          end

          def noted?(id)
            @boxes.each_value.any? do |box|
              box.node.dig(:metadata, :note_target) == id
            end
          end

          def straight(source, target)
            from = @boxes.fetch(source)
            to = @boxes.fetch(target)
            [border(from, centre(to)), border(to, centre(from))]
          end

          def spread(routed)
            groups = routed.group_by { |edge, _| pair_key(edge) }
            groups.flat_map { |key, group| spread_group(key, group) }
          end

          def spread_group(key, group)
            group.each_with_index.map do |(edge, points), index|
              slot = Slot.new(index, group.size, 0.0)
              slot.offset = slot.lane * SPREAD
              [edge, move(points, key, slot.offset), slot]
            end
          end

          def pair_key(edge)
            [edge[:sources].first, edge[:targets].first].sort
          end

          # Parts a route from the others of its pair, across the line
          # between the two states taken in one fixed order so a pair's two
          # directions part ways. A straight route bows through one bend
          # point; a longer one moves over.
          def move(points, key, offset)
            return points if offset.zero? || key.first == key.last

            from = centre(@boxes.fetch(key.first))
            to = centre(@boxes.fetch(key.last))
            return bowed(points, from, to, offset) if points.size == 2

            sideways(points, from, to, offset)
          end
        end
      end
    end
  end
end
