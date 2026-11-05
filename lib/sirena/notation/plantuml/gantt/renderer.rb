# frozen_string_literal: true

require_relative "../../../renderer/gantt"
require_relative "../../../svg/polygon"

module Sirena
  module Notation
    module PlantUML
      module Gantt
        # Draws a PlantUML gantt scene: grey table and day grid, lilac bars
        # with a dark outline. The Mermaid renderer it extends draws a dated
        # axis over coloured sections.
        class Renderer < Sirena::Renderer::Gantt
          GRID = "#C0C0C0"
          INK = "#181818"
          BAR_FILL = "#E2E2F0"
          private_constant :GRID, :INK, :BAR_FILL

          # @param scene [Gantt::Scene] final canvas geometry
          # @return [Svg::Document]
          def render(scene)
            validate_scene!(scene)
            svg = create_document(scene)
            draw_grid(scene, svg)
            draw_marks(scene, svg)
            scene.texts.each { |label| svg << text_element(label) }
            svg
          end

          private

          def draw_grid(scene, svg)
            scene.grid_lines.each { |line| svg << stroked(line, GRID) }
            scene.bars.each { |bar| bars(bar, svg) }
          end

          def draw_marks(scene, svg)
            scene.diamonds.each { |points| svg << diamond(points) }
            scene.rules.each { |line| svg << stroked(line, INK) }
          end

          def stroked(geometry, colour)
            Svg::Line.new.tap do |line|
              apply_line_geometry(line, geometry)
              line.stroke = colour
              line.stroke_width = "1"
            end
          end

          def bars(geometry, svg)
            svg << Svg::Rect.new.tap do |rect|
              apply_rect_geometry(rect, geometry)
              rect.fill = BAR_FILL
              rect.stroke = INK
              rect.stroke_width = "1"
            end
          end

          def diamond(points)
            Svg::Polygon.new.tap do |polygon|
              polygon.points = points
              polygon.fill = INK
              polygon.stroke = INK
              polygon.stroke_width = "1"
            end
          end

          def apply_text_style(text, geometry, fill)
            super
            text.font_family = "sans-serif"
          end

          def apply_text_geometry(text, geometry)
            super
            text.dominant_baseline = nil
          end
        end
      end
    end
  end
end
