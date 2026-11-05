# frozen_string_literal: true

require_relative "../../../renderer/mindmap"

module Sirena
  module Notation
    module PlantUML
      module Tree
        # Draws a PlantUML tree: grey boxes with a dark outline, text set
        # from the left of the box, and thin dark connectors under them. The
        # Mermaid mindmap renderer it extends draws coloured, centred shapes.
        class Renderer < Sirena::Renderer::Mindmap
          INK = "#181818"
          FONT = "sans-serif"
          private_constant :INK, :FONT

          protected

          def render_connection(edge, svg)
            svg.add_element(Svg::Path.new.tap do |path|
              path.d = edge.path
              path.stroke = INK
              path.stroke_width = edge.stroke_width.to_s
              path.fill = "none"
            end)
          end

          def render_node(node, svg)
            group = Svg::Group.new
            group.add_child(outline(node)) if node.boxed
            label = node.labels.first
            label.lines.each do |line|
              group.add_child(text_line(line, label.font_size))
            end
            svg.add_element(group)
          end

          private

          def outline(node)
            Svg::Rect.new(x: node.x, y: node.y, width: node.width,
                          height: node.height, rx: node.corner_radius,
                          ry: node.corner_radius, fill: node.fill,
                          stroke: INK, stroke_width: "1.5")
          end

          def text_line(line, size)
            Svg::Text.new.tap do |text|
              text.x = line.x
              text.y = line.y
              text.content = line.text
              text.fill = "#000000"
              text.font_size = size.to_s
              text.font_family = FONT
            end
          end
        end
      end
    end
  end
end
