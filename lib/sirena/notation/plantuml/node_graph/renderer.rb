# frozen_string_literal: true

require_relative "../../../renderer/base"
require_relative "../../../svg"
require_relative "heads"
require_relative "layout"
require_relative "shapes"

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # Draws a {Scene}: containers, then links, then nodes, then labels.
        class Renderer < Sirena::Renderer::Base
          INK = "#181818"
          DASH = "5,4"
          NAMED = /\A[A-Za-z]+\z/

          # @param scene [Scene]
          # @return [Svg::Document]
          def render(scene)
            Svg::Document.new(width: scene.width, height: scene.height,
                              view_box: "0 0 #{scene.width} #{scene.height}")
              .tap do |document|
              elements(scene).each { |element| document << element }
            end
          end

          private

          def elements(scene)
            containers, leaves = scene.placed.partition do |box|
              box.node.container?
            end
            [*drawn(containers.sort_by(&:depth)), *scene.routes.flat_map do |r|
              link(r)
            end, *drawn(leaves), *labels(scene), *title(scene)]
          end

          def drawn(boxes)
            shapes = Shapes.new
            boxes.flat_map { |box| shapes.draw(box) }
          end

          def labels(scene)
            scene.routes.filter_map { |route| label(route) }
          end

          def title(scene)
            return [] unless scene.title

            [text(scene.width / 2, 22, scene.title, "bold")]
          end

          def link(route)
            edge = route.edge
            color = ink(edge.color)
            [line(route.points, edge, color),
             *Heads.for(edge, *route.points, color)]
          end

          def line(points, edge, color)
            Svg::Line.new.tap do |line|
              line.x1, line.y1 = points.first
              line.x2, line.y2 = points.last
              stroke(line, edge, color)
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

          def label(route)
            return if route.edge.label.to_s.empty?

            x_mid, y_mid = route.points.transpose.map { |v| v.sum / 2 }
            text(x_mid, y_mid - 4, route.edge.label)
          end

          def text(x_pos, y_pos, content, weight = nil)
            Svg::Text.new.tap do |node|
              node.x = x_pos
              node.y = y_pos
              node.content = content
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
end
