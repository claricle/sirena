# frozen_string_literal: true

require_relative "../../renderer/base"
require_relative "../../svg"
require_relative "scene"

module Sirena
  module Notation
    module PlantUML
      # Draws a PlantUML Scene without changing any of its geometry.
      class Renderer < Sirena::Renderer::Base
        BOLD_ROLES = %w[class_name package_title].freeze
        private_constant :BOLD_ROLES

        def render(scene)
          document = Svg::Document.new(
            width: scene.width,
            height: scene.height,
            view_box: "0 0 #{scene.width} #{scene.height}",
          )
          scene.frames.each { |frame| render_frame(frame, document) }
          scene.relations.each do |relation|
            render_relation(relation, document)
          end
          scene.boxes.each { |box| render_box(box, document) }
          document
        end

        private

        def render_frame(frame, document)
          group = Svg::Group.new(id: frame.id)
          group << frame_rectangle(frame.x, frame.y, frame.width, frame.height)
          group << frame_tab(frame) if frame.tab_width
          group << package_icon(frame) if frame.icon
          frame.texts.each { |text| group << text_element(text) }
          document << group
        end

        # A folder's tab sits on top of the body; a frame has none.
        def frame_tab(frame)
          frame_rectangle(frame.x, frame.y, frame.tab_width, 22.0)
        end

        def frame_rectangle(x, y, width, height)
          Svg::Rect.new.tap do |rectangle|
            rectangle.x = x
            rectangle.y = y
            rectangle.width = width
            rectangle.height = height
            rectangle.fill = "none"
            rectangle.stroke = node_stroke
            rectangle.stroke_width = stroke_width
          end
        end

        def package_icon(frame)
          Svg::Circle.new.tap do |circle|
            circle.cx = frame.x + 12.0
            circle.cy = frame.y + 11.0
            circle.r = 3.0
            circle.fill = "#84be84"
            circle.stroke = "#038048"
          end
        end

        def render_relation(relation, document)
          group = Svg::Group.new(id: relation.id)
          group << relation_line(relation)
          group << relation_marker(relation) if relation.marker_points
          relation.texts.each { |text| group << text_element(text) }
          document << group
        end

        def relation_line(relation)
          Svg::Path.new.tap do |path|
            path.d = relation.path
            path.fill = "none"
            path.stroke = edge_colour
            path.stroke_width = stroke_width
            path.stroke_dasharray = "6,4" if relation.dashed
          end
        end

        def relation_marker(relation)
          Svg::Polygon.new.tap do |polygon|
            polygon.points = relation.marker_points
            polygon.fill = relation.marker_filled ? edge_colour : node_fill
            polygon.stroke = edge_colour
            polygon.stroke_width = stroke_width
          end
        end

        def render_box(box, document)
          group = Svg::Group.new(id: box_id(box))
          group << box_rectangle(box)
          box.separators.each { |separator| group << separator_line(separator) }
          box.texts.each { |text| group << text_element(text) }
          document << group
        end

        def box_id(box)
          box.kind == "note" ? box.id : "class-#{box.id}"
        end

        def box_rectangle(box)
          Svg::Rect.new.tap do |rectangle|
            apply_box_geometry(rectangle, box)
            apply_box_style(rectangle)
            rectangle.fill = note_fill(box) if box.kind == "note"
          end
        end

        def apply_box_geometry(rectangle, box)
          rectangle.x = box.x
          rectangle.y = box.y
          rectangle.width = box.width
          rectangle.height = box.height
          rectangle.rx = 3
          rectangle.ry = 3
        end

        def apply_box_style(rectangle)
          rectangle.fill = node_fill
          rectangle.stroke = node_stroke
          rectangle.stroke_width = stroke_width
        end

        # `#yellow` is a colour name and `#FFAA00` a hex value.
        def note_fill(box)
          colour = box.fill&.delete_prefix("#")
          return "#fbfb77" unless colour
          return "##{colour}" if colour.match?(/\A\h{3}(?:\h{3})?\z/)

          colour
        end

        def separator_line(segment)
          Svg::Line.new.tap do |line|
            line.x1 = segment.x1
            line.y1 = segment.y1
            line.x2 = segment.x2
            line.y2 = segment.y2
            line.stroke = node_stroke
            line.stroke_width = "1"
          end
        end

        def text_element(scene_text)
          Svg::Text.new.tap do |text|
            apply_text_geometry(text, scene_text)
            apply_text_style(text, scene_text.role)
          end
        end

        def apply_text_geometry(text, scene_text)
          text.x = scene_text.x
          text.y = scene_text.y
          text.content = scene_text.content
          text.text_anchor = scene_text.anchor
        end

        def apply_text_style(text, role)
          text.fill = text_colour
          text.font_family = font_family(role)
          text.font_size = font_size(role)
          text.font_weight = "bold" if BOLD_ROLES.include?(role)
          text.font_style = "italic" if %w[kind member_abstract].include?(role)
        end

        def font_family(role)
          return "monospace" if role.start_with?("member")

          theme_typography(:font_family) || "Arial, sans-serif"
        end

        def font_size(role)
          normal = theme_typography(:font_size_normal) || 14
          return (normal.to_f * 0.85).to_s if role == "kind"

          small_roles = %w[multiplicity relation_label]
          return (normal.to_f * 0.9).to_s if small_roles.include?(role)

          normal.to_s
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
