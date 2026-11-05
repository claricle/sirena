# frozen_string_literal: true

require_relative "../../plantuml_data/boxes/table_box"
require_relative "metrics"
require_relative "packer"
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
          # A cloud's outline is an ellipse, so it needs this much more room
          # on each side before its corners clear what it holds.
          CLOUD_ROOM = 0.45

          # @param graph [Graph]
          # @return [Scene]
          def call(graph, **)
            @graph = graph
            @sizes = {}
            @inner = {}
            @inset = {}
            top = arrange(nil)
            placed = []
            place(top.offsets, [MARGIN, MARGIN + title_room], 0, placed)
            scene(top, placed)
          end

          private

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
            children = @graph.children_of(scope)
            children.each { |child| measure(child) }
            ranking = Ranking.new(children, pairs(scope))
            packed = Packer.new(@sizes, left_to_right: left_to_right?)
              .pack(ranking.layers)
            scope ? frame(packed, scope) : packed
          end

          def left_to_right?
            @graph.direction == :left_to_right
          end

          def frame(packed, scope)
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

            width, height = @sizes[node]
            inset = @inset[node] = [width * CLOUD_ROOM, height * CLOUD_ROOM]
            @sizes[node] = [width, height].zip(inset).map do |size, room|
              size + (2 * room)
            end
          end

          def pairs(scope)
            @graph.edges.filter_map do |edge|
              from = lift(edge.from, scope)
              to = lift(edge.to, scope)
              ranked(edge, from, to) if from && to && !from.equal?(to)
            end
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

          def place(offsets, origin, depth, placed)
            offsets.each do |node, (x_pos, y_pos)|
              width, height = @sizes[node]
              placed << Placed.new(node: node, x: origin[0] + x_pos,
                                   y: origin[1] + y_pos, width: width,
                                   height: height, depth: depth)
              place_inside(placed.last, depth, placed) if node.container?
            end
          end

          def place_inside(box, depth, placed)
            place(@inner[box.node].offsets, inside_origin(box), depth + 1,
                  placed)
          end

          def inside_origin(box)
            room = @inset.fetch(box.node, [0.0, 0.0])
            [box.x + PAD + room[0],
             box.y + PAD + room[1] + Metrics.header_height(box.node)]
          end

          def routes(placed)
            boxes = placed.to_h { |box| [box.node, box] }
            @graph.edges.filter_map do |edge|
              from = boxes[edge.from]
              to = boxes[edge.to]
              next if from.equal?(to)

              Route.new(edge: edge, points: segment(from, to, edge))
            end
          end

          def segment(from, to, edge)
            a = center(from)
            b = center(to)
            [row_end(from, edge.from_row, b) || clip(from, a, b),
             row_end(to, edge.to_row, a) || clip(to, b, a)]
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
