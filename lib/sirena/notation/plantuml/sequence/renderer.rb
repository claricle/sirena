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
          # Back to front: the scene collection and the method drawing each
          # of its items.
          LAYERS = [
            %i[frames frame_group], %i[lifelines lifeline],
            %i[fragments fragment_group], %i[dividers divider_group],
            %i[arrows arrow_group], %i[notes note_group],
            %i[heads head_group]
          ].freeze
          private_constant :LAYERS

          def render(scene)
            document = blank_document(scene)
            LAYERS.each do |collection, drawer|
              items = scene.public_send(collection)
              items.each { |item| document << send(drawer, item) }
            end
            document
          end

          private

          def blank_document(scene)
            Svg::Document.new(
              width: scene.width, height: scene.height,
              view_box: "0 0 #{scene.width} #{scene.height}"
            )
          end

          # Assigns every attribute that is not nil.
          def element(type, **attributes)
            type.new.tap do |node|
              attributes.each do |name, value|
                node.public_send(:"#{name}=", value) unless value.nil?
              end
            end
          end

          def group(id, children, texts)
            Svg::Group.new(id: id).tap do |group|
              children.each { |child| group << child }
              texts.each { |text| group << text_element(text) }
            end
          end

          def frame_group(frame)
            group("box-#{frame.x}", [frame_rectangle(frame)], frame.texts)
          end

          def frame_rectangle(frame)
            element(Svg::Rect, x: frame.x, y: frame.y, width: frame.width,
                               height: frame.height, fill: "none",
                               stroke: node_stroke, stroke_width: "1")
          end

          def lifeline(segment)
            element(Svg::Line, x1: segment.x1, y1: segment.y1,
                               x2: segment.x2, y2: segment.y2,
                               stroke: node_stroke, stroke_width: "1",
                               stroke_dasharray: "5,5")
          end

          def arrow_group(arrow)
            group(arrow.id, [arrow_path(arrow), arrow_head(arrow)],
                  arrow.texts)
          end

          def arrow_path(arrow)
            element(Svg::Path, d: arrow.path, fill: "none",
                               stroke: edge_colour, stroke_width: stroke_width,
                               stroke_dasharray: arrow.dashed ? "6,4" : nil)
          end

          def arrow_head(arrow)
            fill = arrow.marker_filled ? edge_colour : node_fill
            element(Svg::Polygon, points: arrow.marker_points, fill: fill,
                                  stroke: edge_colour,
                                  stroke_width: stroke_width)
          end

          def fragment_group(fragment)
            children = [frame_rectangle(fragment),
                        outlined_path(fragment.tab_path, node_fill),
                        *fragment.separators.map { |line| dashed(line) }]
            group("fragment-#{fragment.x}-#{fragment.y}", children,
                  fragment.texts)
          end

          def note_group(note)
            children = [outlined_path(note.path, note_fill)]
            if note.fold_path
              children << outlined_path(note.fold_path, note_fill)
            end
            group("note-#{note.path.hash.abs}", children, note.texts)
          end

          def divider_group(divider)
            children = divider.lines.map { |line| solid(line) }
            children << divider_label(divider) unless divider.texts.empty?
            group("divider-#{divider.y}", children, divider.texts)
          end

          def divider_label(divider)
            element(Svg::Rect, x: divider.x, y: divider.y, width: divider.width,
                               height: divider.height, fill: node_fill,
                               stroke: node_stroke, stroke_width: "1")
          end

          def outlined_path(data, fill)
            element(Svg::Path, d: data, fill: fill, stroke: node_stroke,
                               stroke_width: "1")
          end

          def solid(segment)
            lifeline(segment).tap { |line| line.stroke_dasharray = nil }
          end

          def dashed(segment)
            lifeline(segment).tap { |line| line.stroke_dasharray = "5,3" }
          end

          def head_group(head)
            group("participant-#{head.id}-#{head.y}", [head_rectangle(head)],
                  head.texts)
          end

          def head_rectangle(head)
            element(Svg::Rect, x: head.x, y: head.y, width: head.width,
                               height: head.height, rx: 3, ry: 3,
                               fill: node_fill, stroke: node_stroke,
                               stroke_width: stroke_width)
          end

          def text_element(scene_text)
            element(Svg::Text, x: scene_text.x, y: scene_text.y,
                               content: scene_text.content,
                               text_anchor: scene_text.anchor,
                               fill: text_colour, font_family: font_family,
                               font_size: font_size(scene_text.role),
                               font_style: text_style(scene_text.role),
                               font_weight: text_weight(scene_text.role))
          end

          def font_family
            theme_typography(:font_family) || "Arial"
          end

          def text_style(role)
            "italic" if role == "kind"
          end

          def text_weight(role)
            "bold" if role == "fragment_tab"
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
