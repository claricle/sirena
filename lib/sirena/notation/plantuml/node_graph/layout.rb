# frozen_string_literal: true

require_relative "../../../text_measurement"
require_relative "../../plantuml_data/boxes/table_box"
require_relative "detour"
require_relative "frame_ports"
require_relative "metrics"
require_relative "packer"
require_relative "paths"
require_relative "ranking"
require_relative "scene"

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # Places a {Graph}: each container lays out its own children in
        # ranks, outermost container last. Links are cut at the box edges.
        class Layout
          MARGIN = 16.0
          PAD = 16.0
          TITLE_HEIGHT = 30.0
          # A cloud's cut, bumped outline needs this much more room on each
          # side, across and down, before it clears what it holds.
          CLOUD_ROOM = [22.0, 19.0].freeze

          # @param graph [Graph]
          # @return [Scene]
          def call(graph, **)
            reset(graph)
            top = arrange(nil)
            placed = []
            place(top, [MARGIN, MARGIN + title_room], 0, placed)
            scene(top, placed)
          end

          private

          def reset(graph)
            @graph = graph
            @sizes = {}
            @frame_ports = FramePorts.new(@sizes)
            @ports = {}
            @inner = {}
            @inset = {}
            @paths = Paths.new(left_to_right? ? 0 : 1)
          end

          def scene(top, placed)
            Scene.new(width: [top.width + (2 * MARGIN), title_width].max,
                      height: top.height + (2 * MARGIN) + title_room,
                      placed: placed, routes: routes(placed),
                      title: @graph.title)
          end

          def title_room
            @graph.title ? TITLE_HEIGHT : 0.0
          end

          def title_width
            return 0.0 unless @graph.title

            Metrics.text_width([@graph.title]) + (2 * MARGIN)
          end

          # Lays out the children of `scope` and records their sizes.
          def arrange(scope)
            ports, children = split_ports(scope)
            (ports + children).each { |child| measure(child) }
            ranking = Ranking.new(children, pairs(scope))
            packed = pack(ranking, scope)
            scope ? frame(packed, scope, ports) : packed
          end

          def pack(ranking, scope)
            packer = Packer.new(@sizes, left_to_right: left_to_right?,
                                        reach: label_reach(scope))
            packer.route(packer.pack(ranking.layers), ranking.chains)
          end

          # How wide the widest label on a link of each item of `scope` is:
          # neighbours are kept this far apart so the labels fan out.
          def label_reach(scope)
            @graph.edges.each_with_object(Hash.new(0.0)) do |edge, reach|
              width = label_width(edge)
              ends(edge, scope).each do |item|
                reach[item] = [reach[item], width].max
              end
            end
          end

          def ends(edge, scope)
            [edge.from, edge.to].filter_map { |node| lift(node, scope) }
          end

          def label_width(edge)
            text = edge.label.to_s
            return 0.0 if text.empty?

            TextMeasurement.measure(text, font_size: 12)[:width].to_f
          end

          # The children of `scope` on its frame, then the rest.
          def split_ports(scope)
            @graph.children_of(scope).partition do |node|
              FramePorts.on_frame?(node)
            end.tap { |ports, _| @ports[scope] = ports }
          end

          def left_to_right?
            @graph.direction == :left_to_right
          end

          def frame(packed, scope, ports)
            packed.width = [packed.width, @frame_ports.width(ports)].max
            packed.width += 2 * PAD
            packed.height += (2 * PAD) + Metrics.header_height(scope)
            packed
          end

          def measure(node)
            return @sizes[node] = Metrics.size(node) unless node.container?

            inner = @inner[node] = arrange(node)
            @sizes[node] = [[inner.width, Metrics.header_width(node)].max,
                            inner.height]
            inflate_cloud(node)
          end

          def inflate_cloud(node)
            return @sizes[node] unless node.kind == :cloud

            inset = @inset[node] = CLOUD_ROOM
            @sizes[node] = @sizes[node].zip(inset).map do |size, room|
              size + (2 * room)
            end
          end

          def pairs(scope)
            @graph.edges.filter_map do |edge|
              from = lift(edge.from, scope)
              to = lift(edge.to, scope)
              ranked(edge, from, to) if inner?(from, to)
            end
          end

          # Whether a link is between two items that take part in ranking.
          def inner?(from, to)
            return false unless from && to && !from.equal?(to)

            [from, to].none? { |node| FramePorts.on_frame?(node) }
          end

          # `[from, to, step]`, the ends swapped when the link reads backwards.
          def ranked(edge, from, to)
            ends = edge.backwards ? [to, from] : [from, to]
            [*ends, edge.rank_step]
          end

          def lift(node, scope)
            chain = node.ancestors + [node]
            return chain.first unless scope

            at = chain.index { |entry| entry.equal?(scope) }
            at && chain[at + 1]
          end

          def place(packed, origin, depth, placed)
            @paths.record(packed.paths, origin)
            packed.offsets.each do |node, (x_pos, y_pos)|
              width, height = @sizes[node]
              placed << Placed.new(node: node, x: origin[0] + x_pos,
                                   y: origin[1] + y_pos, width: width,
                                   height: height, depth: depth)
              place_inside(placed.last, depth, placed) if node.container?
            end
          end

          def place_inside(box, depth, placed)
            place(@inner[box.node], inside_origin(box), depth + 1, placed)
            placed.concat(@frame_ports.place(box, @ports[box.node], depth + 1))
          end

          def inside_origin(box)
            room = @inset.fetch(box.node, [0.0, 0.0])
            [box.x + PAD + room[0],
             box.y + PAD + room[1] + Metrics.header_height(box.node)]
          end

          def routes(placed)
            boxes = placed.to_h { |box| [box.node, terminal(box)] }
            detour = Detour.new(placed)
            @graph.edges.filter_map { |edge| route(edge, boxes, detour) }
          end

          def route(edge, boxes, detour)
            from, to = boxes.values_at(edge.from, edge.to)
            return if from.equal?(to)

            points = segment(from, to, edge, @paths.between(edge, center(from)))
            Route.new(edge: edge, points: bent(detour, edge, points))
          end

          # A note's pointer and a line to a row stay straight.
          def bent(detour, edge, points)
            straight = edge.pointer || edge.from_row || edge.to_row
            straight ? points : detour.call(edge, points)
          end

          # What a link ends at: the square of a port on a frame, otherwise
          # the box itself.
          def terminal(box)
            FramePorts.on_frame?(box.node) ? @frame_ports.terminal(box) : box
          end

          # `between` is where a link across ranks passes the ranks it
          # skips.
          def segment(from, to, edge, between)
            a = center(from)
            b = center(to)
            [end_at(from, edge.from_row, a, between.first || b),
             *between,
             end_at(to, edge.to_row, b, between.last || a)]
          end

          def end_at(box, row, inner, toward)
            row_end(box, row, toward) || clip(box, inner, toward)
          end

          # The middle of the row of a map or object box that a line ends
          # at, on the side facing `toward`.
          def row_end(box, row, toward)
            return unless row

            side = toward[0] >= center(box)[0] ? box.x + box.width : box.x
            [side, PlantUMLData::Boxes::TableBox
              .row_middle(box.node.table, row, box.y)]
          end

          def center(box)
            [box.x + (box.width / 2), box.y + (box.height / 2)]
          end

          # The point where the line from `inner` toward `outer` leaves `box`.
          def clip(box, inner, outer)
            delta = [outer[0] - inner[0], outer[1] - inner[1]]
            return inner if delta.all?(&:zero?)

            scale = exit_scale(box, delta)
            inner.zip(delta).map { |pos, change| pos + (change * scale) }
          end

          def exit_scale(box, delta)
            [box.width, box.height].zip(delta).map do |extent, change|
              extent / 2 / (change.abs.nonzero? || 1e-9)
            end.min
          end
        end
      end
    end
  end
end
