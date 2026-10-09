# frozen_string_literal: true

require_relative "../../../renderer/base"
require_relative "../../../svg"
require_relative "scene"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # Draws a sequence Scene without changing its geometry.
        class Renderer < Sirena::Renderer::Base
          def render(scene)
            document = Svg::Document.new(
              width: scene.width, height: scene.height,
              view_box: "0 0 #{scene.width} #{scene.height}"
            )
            scene.frames.each { |frame| document << frame_group(frame) }
            scene.lifelines.each { |line| document << lifeline(line) }
            scene.fragments.each { |item| document << fragment_group(item) }
            scene.dividers.each { |item| document << divider_group(item) }
            scene.arrows.each { |arrow| document << arrow_group(arrow) }
            scene.notes.each { |item| document << note_group(item) }
            scene.heads.each { |head| document << head_group(head) }
            document
          end

          private

          def frame_group(frame)
            group = Svg::Group.new(id: "box-#{frame.x}")
            group << frame_rectangle(frame)
            frame.texts.each { |text| group << text_element(text) }
            group
          end

          def frame_rectangle(frame)
            Svg::Rect.new.tap do |rect|
              rect.x = frame.x
              rect.y = frame.y
              rect.width = frame.width
              rect.height = frame.height
              rect.fill = "none"
              rect.stroke = node_stroke
              rect.stroke_width = "1"
            end
          end

          def lifeline(segment)
            Svg::Line.new.tap do |line|
              line.x1 = segment.x1
              line.y1 = segment.y1
              line.x2 = segment.x2
              line.y2 = segment.y2
              line.stroke = node_stroke
              line.stroke_width = "1"
              line.stroke_dasharray = "5,5"
            end
          end

          def arrow_group(arrow)
            group = Svg::Group.new(id: arrow.id)
            group << arrow_path(arrow)
            group << arrow_head(arrow)
            arrow.texts.each { |text| group << text_element(text) }
            group
          end

          def arrow_path(arrow)
            Svg::Path.new.tap do |path|
              path.d = arrow.path
              path.fill = "none"
              path.stroke = edge_colour
              path.stroke_width = stroke_width
              path.stroke_dasharray = "6,4" if arrow.dashed
            end
          end

          def arrow_head(arrow)
            Svg::Polygon.new.tap do |polygon|
              polygon.points = arrow.marker_points
              polygon.fill = arrow.marker_filled ? edge_colour : node_fill
              polygon.stroke = edge_colour
              polygon.stroke_width = stroke_width
            end
          end

          def fragment_group(fragment)
            group = Svg::Group.new(id: "fragment-#{fragment.x}-#{fragment.y}")
            group << frame_rectangle(fragment)
            group << outlined_path(fragment.tab_path, node_fill)
            fragment.separators.each { |line| group << dashed(line) }
            fragment.texts.each { |text| group << text_element(text) }
            group
          end

          def note_group(note)
            group = Svg::Group.new(id: "note-#{note.path.hash.abs}")
            group << outlined_path(note.path, note_fill)
            group << outlined_path(note.fold_path, note_fill) if note.fold_path
            note.texts.each { |text| group << text_element(text) }
            group
          end

          def divider_group(divider)
            group = Svg::Group.new(id: "divider-#{divider.y}")
            divider.lines.each { |line| group << solid(line) }
            group << divider_label(divider) unless divider.texts.empty?
            divider.texts.each { |text| group << text_element(text) }
            group
          end

          def divider_label(divider)
            Svg::Rect.new.tap do |rect|
              rect.x = divider.x
              rect.y = divider.y
              rect.width = divider.width
              rect.height = divider.height
              rect.fill = node_fill
              rect.stroke = node_stroke
              rect.stroke_width = "1"
            end
          end

          def outlined_path(data, fill)
            Svg::Path.new.tap do |path|
              path.d = data
              path.fill = fill
              path.stroke = node_stroke
              path.stroke_width = "1"
            end
          end

          def solid(segment)
            lifeline(segment).tap { |line| line.stroke_dasharray = nil }
          end

          def dashed(segment)
            lifeline(segment).tap { |line| line.stroke_dasharray = "5,3" }
          end

          def head_group(head)
            group = Svg::Group.new(id: "participant-#{head.id}-#{head.y}")
            group << head_rectangle(head)
            head.texts.each { |text| group << text_element(text) }
            group
          end

          def head_rectangle(head)
            Svg::Rect.new.tap do |rect|
              rect.x = head.x
              rect.y = head.y
              rect.width = head.width
              rect.height = head.height
              rect.rx = 3
              rect.ry = 3
              rect.fill = node_fill
              rect.stroke = node_stroke
              rect.stroke_width = stroke_width
            end
          end

          def text_element(scene_text)
            Svg::Text.new.tap do |text|
              text.x = scene_text.x
              text.y = scene_text.y
              text.content = scene_text.content
              text.text_anchor = scene_text.anchor
              text.fill = text_colour
              text.font_family = theme_typography(:font_family) || "Arial"
              text.font_size = font_size(scene_text.role)
              text.font_style = "italic" if scene_text.role == "kind"
            text.font_weight = "bold" if scene_text.role == "fragment_tab"
            end
          end

          def font_size(role)
            normal = theme_typography(:font_size_normal) || 14
            return (normal.to_f * 0.85).to_s if role == "kind"

            normal.to_s
          end

          def note_fill
            theme_color(:note_fill) || "#fefecd"
          end

          def node_fill
            theme_color(:node_fill) || "#ffffff"
          end

          def node_stroke
            theme_color(:node_stroke) || "#333333"
          end

          def edge_colour
            theme_color(:edge_stroke) || "#333333"
          end

          def text_colour
            theme_color(:label_text) || "#111111"
          end

          def stroke_width
            (theme_shape(:stroke_width) || 2).to_s
          end
        end
      end
    end
  end
end
