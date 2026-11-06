# frozen_string_literal: true

require_relative "../../../renderer/base"
require_relative "../../../svg"
require_relative "curve"
require_relative "heads"
require_relative "label_placer"
require_relative "../creole"
require_relative "layout"
require_relative "note_tail"
require_relative "shapes"

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # Draws a {Scene}: containers, then links, then nodes, then labels.
        class Renderer < Sirena::Renderer::Base
          INK = "#181818"
          DASH = "5,4"
          TITLE_SIZE = 13
          SECOND_OFFSET = "translate(2,2)"
          NAMED = /\A[A-Za-z]+\z/

          # @param scene [Scene]
          # @return [Svg::Document]
          def render(scene)
            placements = LabelPlacer.new.call(scene.routes,
                                              [*scene.placed,
                                               *title_area(scene)])
            document(scene, placements).tap do |document|
              elements(scene, placements).each { |item| document << item }
            end
          end

          private

          # Wide and tall enough for the labels as well as the scene.
          def document(scene, placements)
            width = [scene.width, *placements.map(&:right)].max
            height = [scene.height, *placements.map(&:bottom)].max
            Svg::Document.new(width: width, height: height,
                              view_box: "0 0 #{width} #{height}")
          end

          def elements(scene, placements)
            containers, leaves = scene.placed.partition do |box|
              box.node.container?
            end
            [*drawn(containers.sort_by(&:depth)), *scene.routes.flat_map do |r|
              link(r)
            end, *drawn(leaves), *labels(placements), *title(scene)]
          end

          def drawn(boxes)
            shapes = Shapes.new
            boxes.flat_map { |box| shapes.draw(box) }
          end

          def labels(placements)
            placements.map do |placed|
              text(placed.x, placed.y, placed.route.edge.label)
            end
          end

          # The room the title takes, which no label covers.
          def title_area(scene)
            return [] unless scene.title

            width = Drawing::Face.width(scene.title, size: TITLE_SIZE)
            [Placed.new(x: (scene.width - width) / 2, y: 8.0, width: width,
                        height: 18.0)]
          end

          def title(scene)
            return [] unless scene.title

            [text(scene.width / 2, 22, scene.title, "bold")]
          end

          # A note's pointer is a pale triangle from the note to its target.
          def link(route)
            edge = route.edge
            return [NoteTail.new(route.points).element] if note?(edge)

            points = route.points
            [line(points, edge, ink(edge.color)), *heads(points, edge),
             *second_stroke(points, edge)]
          end

          def heads(points, edge)
            Heads.for(edge, points.first, points.last, ink(edge.color),
                      [points[1], points[-2]])
          end

          # PlantUML draws `-[#blue;#green]->` as the line in each colour, the
          # second two units right and down (measured on 1.2026.6).
          def second_stroke(points, edge)
            return [] unless edge.color2

            [line(points, edge, ink(edge.color2)).tap do |copy|
              copy.transform = SECOND_OFFSET
            end]
          end

          def note?(edge)
            edge.pointer
          end

          def line(points, edge, color)
            return bent(points, edge, color) if points.size > 2

            Svg::Line.new.tap do |line|
              line.x1, line.y1 = points.first
              line.x2, line.y2 = points.last
              stroke(line, edge, color)
            end
          end

          def bent(points, edge, color)
            Svg::Path.new.tap do |path|
              path.d = Curve.path(points)
              path.fill = "none"
              stroke(path, edge, color)
            end
          end

          def stroke(line, edge, color)
            line.stroke = color
            line.stroke_width = edge.width.to_s
            line.stroke_dasharray = DASH if edge.style == :dashed
          end

          def ink(color)
            return INK unless color

            color.match?(NAMED) ? color : "##{color}"
          end

          def text(x_pos, y_pos, content, weight = nil)
            Svg::Text.new.tap do |node|
              node.x = x_pos
              node.y = y_pos
              style_text(node, weight)
              Creole.assign(node, content)
            end
          end

          def style_text(node, weight)
            node.text_anchor = "middle"
            node.font_family = "sans-serif"
            node.font_size = "12"
            node.font_weight = weight
            node.fill = "#000000"
          end
        end
      end
    end
  end
end
