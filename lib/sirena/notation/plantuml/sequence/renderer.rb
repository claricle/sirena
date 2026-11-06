# frozen_string_literal: true

require "zlib"
require_relative "../../../renderer/base"
require_relative "../../../svg"
require_relative "scene"
require_relative "skin"
require_relative "../creole"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # Draws a sequence Scene without changing its geometry.
        class Renderer < Sirena::Renderer::Base
          include Skin

          # Back to front: the scene collection and the method drawing each
          # of its items.
          LAYERS = [
            %i[banners banner_group], %i[frames frame_group],
            %i[lifelines lifeline],
            %i[bars activation_bar], %i[crosses cross_line],
            %i[page_breaks page_break_line],
            %i[fragments fragment_group], %i[dividers divider_group],
            %i[delays delay_group],
            %i[arrows arrow_group], %i[notes note_group],
            %i[heads head_group]
          ].freeze
          BANNER_FILL = "#FFFFCC"
          BANNER_STROKE = "#FFDD88"
          WARNING_SIZE = "10"
          LEGEND_FILL = "#DDDDDD"
          HEAD_SHAPE_DRAWERS = {
            rectangles: :head_rectangle,
            ellipses: :head_ellipse,
            paths: :head_path,
            lines: :head_line,
            polygons: :head_polygon,
          }.freeze
          private_constant :LAYERS, :BANNER_FILL, :BANNER_STROKE,
                           :WARNING_SIZE, :LEGEND_FILL, :HEAD_SHAPE_DRAWERS

          def render(scene)
            read_painted(scene)
            document = blank_document(scene)
            background(document, scene)
            chrome_groups(document, scene)
            LAYERS.each do |collection, drawer|
              items = scene.public_send(collection)
              items&.each { |item| document << send(drawer, item) }
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

          def background(document, scene)
            return unless painted(:background)

            document << element(Svg::Rect, x: 0, y: 0, width: scene.width,
                                           height: scene.height,
                                           fill: painted(:background))
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

          def chrome_groups(document, scene)
            document << title_group(scene.title) if scene.title
            scene.text_blocks.each { |block| document << block_group(block) }
            document << legend_group(scene.legend) if scene.legend
          end

          def block_group(block)
            group(block.id, [], block.texts)
          end

          def legend_group(legend)
            frame = element(Svg::Rect, x: legend.x, y: legend.y,
                                       width: legend.width,
                                       height: legend.height, rx: 7.5, ry: 7.5,
                                       fill: LEGEND_FILL, stroke: "#000000",
                                       stroke_width: "1")
            group("legend", [frame], legend.texts)
          end

          def title_group(title)
            group("title", [], title.texts)
          end

          def banner_group(banner)
            rect = element(Svg::Rect, x: banner.x, y: banner.y,
                                      width: banner.width,
                                      height: banner.height, rx: 2.5, ry: 2.5,
                                      fill: BANNER_FILL, stroke: BANNER_STROKE,
                                      stroke_width: "3")
            group("banner-#{banner.y}", [rect], banner.texts)
          end

          def frame_group(frame)
            group("box-#{frame.x}", [box_rectangle(frame)], frame.texts)
          end

          def frame_rectangle(frame)
            element(Svg::Rect, x: frame.x, y: frame.y, width: frame.width,
                               height: frame.height, fill: "none",
                               stroke: node_stroke, stroke_width: "1")
          end

          def box_rectangle(frame)
            frame_rectangle(frame).tap do |rect|
              rect.fill = box_fill(frame) || rect.fill
              rect.stroke = stroke_of(:box_line, :line, rect.stroke)
              rect.stroke_width = skin_width(:thin) || rect.stroke_width
            end
          end

          def box_fill(frame)
            frame.fill || painted(:box_fill) || skin_paint(:box_fill)
          end

          # The stroke a painted role, then the skin, then the default give.
          def stroke_of(role, skin_key, default)
            painted(role) || skin_paint(skin_key) || default
          end

          def fragment_rectangle(fragment)
            frame_rectangle(fragment).tap do |rect|
              rect.stroke = stroke_of(:group_line, :frame_stroke, rect.stroke)
              rect.stroke_width = skin_width(:frame) || rect.stroke_width
            end
          end

          def activation_bar(bar)
            fill = bar.fill || skin_paint(:bar_fill) || node_fill
            frame_rectangle(bar).tap do |rect|
              rect.fill = fill
              rect.stroke = skin_paint(:line) || rect.stroke
              rect.stroke_width = skin_width(:bar) || rect.stroke_width
            end
          end

          def cross_line(segment)
            solid(segment).tap { |line| line.stroke = edge_colour }
          end

          def page_break_line(segment)
            lifeline(segment).tap { |line| line.stroke_dasharray = "2,2" }
          end

          def lifeline(segment)
            element(Svg::Line, x1: segment.x1, y1: segment.y1,
                               x2: segment.x2, y2: segment.y2,
                               stroke: stroke_of(:lifeline, :line,
                                                 node_stroke),
                               stroke_width: skin_width(:thin) || "1",
                               stroke_dasharray: segment.dash || "5,5")
          end

          def arrow_group(arrow)
            colour = arrow.colour || edge_colour
            marks = arrow.marks.map { |mark| arrow_mark(mark, colour) }
            group(arrow.id, [arrow_path(arrow), *marks], arrow.texts)
          end

          def arrow_path(arrow)
            element(Svg::Path, d: arrow.path, fill: "none",
                               stroke: arrow.colour || edge_colour,
                               stroke_width: stroke_width,
                               stroke_dasharray: arrow_dash(arrow))
          end

          def arrow_dash(arrow)
            skin_dash("6,4") if arrow.dashed
          end

          def arrow_mark(mark, colour)
            case mark.kind
            when "polygon" then mark_polygon(mark, colour)
            when "circle" then mark_circle(mark, colour)
            else mark_line(mark, colour)
            end
          end

          def mark_polygon(mark, colour)
            fill = mark.filled ? colour : mark_open_fill
            element(Svg::Polygon, points: mark.points, fill: fill,
                                  stroke: colour,
                                  stroke_width: stroke_width)
          end

          def mark_circle(mark, colour)
            element(Svg::Circle, cx: mark.cx, cy: mark.cy, r: mark.r,
                                 fill: mark_open_fill, stroke: colour,
                                 stroke_width: stroke_width)
          end

          def mark_open_fill
            skin_paint(:bar_fill) || node_fill
          end

          def mark_line(mark, colour)
            width = mark.heavy ? (stroke_width.to_f * 2).to_s : stroke_width
            element(Svg::Line, x1: mark.x1, y1: mark.y1, x2: mark.x2,
                               y2: mark.y2, stroke: colour,
                               stroke_width: width)
          end

          def fragment_group(fragment)
            children = [fragment_rectangle(fragment),
                        tab_path(fragment),
                        *fragment.separators.map { |line| dashed(line) }]
            group("fragment-#{fragment.x}-#{fragment.y}", children,
                  fragment.texts)
          end

          def tab_path(fragment)
            fill = fragment.tab_fill || skin_paint(:tab_fill) || node_fill
            outlined_path(fragment.tab_path, fill).tap do |path|
              path.stroke = stroke_of(:group_line, :frame_stroke, path.stroke)
              path.stroke_width = skin_width(:frame) || path.stroke_width
            end
          end

          def note_group(note)
            paths = [note.path, note.fold_path].compact
            children = paths.map { |data| note_path(data, note) }
            children << picture_group(note.picture) if note.picture
            group("note-#{Zlib.crc32(note.path)}", children, note.texts)
          end

          # The embedded diagram is drawn by a renderer of its own, in its
          # own units, and scaled into the note.
          def picture_group(picture)
            inner = self.class.new(theme: theme).render(picture.scene)
            at = "translate(#{picture.x}, #{picture.y}) scale(#{picture.scale})"
            Svg::Group.new(transform: at).tap do |group|
              inner.children.each { |child| group << child }
            end
          end

          def note_path(data, note)
            outlined_path(data, note.fill || note_fill).tap do |path|
              path.stroke = stroke_of(:note_line, :line, path.stroke)
              path.stroke_width = skin_width(:thin) || path.stroke_width
              path.fill_opacity = note.fill_opacity&.to_s
            end
          end

          def divider_group(divider)
            children = divider.lines.map { |line| divider_line(line) }
            children << divider_label(divider) unless divider.texts.empty?
            group("divider-#{divider.y}", children, divider.texts)
          end

          def delay_group(delay)
            group("delay-#{delay.texts.first&.y || delay.y1}", [], delay.texts)
          end

          def divider_label(divider)
            element(Svg::Rect, x: divider.x, y: divider.y, width: divider.width,
                               height: divider.height,
                               fill: painted(:divider_fill) || node_fill,
                               stroke: painted(:divider_line) || node_stroke,
                               stroke_width: "1")
          end

          def divider_line(segment)
            solid(segment).tap do |line|
              line.stroke = painted(:divider_line) || line.stroke
            end
          end

          def outlined_path(data, fill)
            element(Svg::Path, d: data, fill: fill, stroke: node_stroke,
                               stroke_width: "1")
          end

          def solid(segment)
            lifeline(segment).tap do |line|
              line.stroke = skin_paint(:frame_stroke) || line.stroke
              line.stroke_width = skin_width(:separator) || line.stroke_width
              line.stroke_dasharray = nil
            end
          end

          def dashed(segment)
            lifeline(segment).tap do |line|
              line.stroke = stroke_of(:group_line, :frame_stroke, line.stroke)
              line.stroke_width = skin_width(:separator) || line.stroke_width
              line.stroke_dasharray = skin_dash("5,3")
            end
          end

          def head_group(head)
            group("participant-#{head.id}-#{head.y}", head_shapes(head),
                  head.texts)
          end

          def head_shapes(head)
            shapes = HEAD_SHAPE_DRAWERS.flat_map do |collection, drawer|
              Array(head.public_send(collection)).map do |shape|
                send(drawer, shape, head)
              end
            end
            return shapes unless shapes.empty?

            [legacy_head_rectangle(head)]
          end

          # v0.1 callers may still construct a Head directly. Its x/y/width/
          # height are already final geometry; this only preserves that Scene
          # input while Layout-published heads use typed primitives above.
          def legacy_head_rectangle(head)
            corner = head_corner(3)
            element(Svg::Rect, x: head.x, y: head.y, width: head.width,
                               height: head.height, rx: corner, ry: corner,
                               fill: head.fill || head_fill,
                               fill_opacity: head.fill_opacity&.to_s,
                               stroke: head.stroke || head_stroke,
                               stroke_width: head_width)
          end

          def head_rectangle(shape, head)
            element(Svg::Rect, x: shape.x, y: shape.y, width: shape.width,
                               height: shape.height, rx: head_corner(shape.rx),
                               ry: head_corner(shape.ry),
                               **head_paint(head))
          end

          def head_paint(head)
            { fill: head.fill || head_fill,
              fill_opacity: head.fill_opacity&.to_s,
              stroke: head.stroke || head_stroke, stroke_width: head_width }
          end

          def head_ellipse(shape, head)
            element(Svg::Ellipse, cx: shape.cx, cy: shape.cy,
                                  rx: shape.rx, ry: shape.ry,
                                  fill: head.fill || head_fill,
                                  fill_opacity: head.fill_opacity&.to_s,
                                  stroke: head.stroke || head_stroke,
                                  stroke_width: head_width)
          end

          def head_path(shape, head)
            fill = shape.filled ? head.fill || head_fill : "none"
            element(Svg::Path, d: shape.data, fill: fill,
                               fill_opacity: head_path_opacity(shape, head),
                               stroke: head.stroke || head_stroke,
                               stroke_width: head_width)
          end

          def head_path_opacity(shape, head)
            head.fill_opacity&.to_s if shape.filled
          end

          def head_line(shape, head)
            element(Svg::Line, x1: shape.x1, y1: shape.y1,
                               x2: shape.x2, y2: shape.y2,
                               stroke: head.stroke || head_stroke,
                               stroke_width: head_width)
          end

          def head_polygon(shape, head)
            colour = head.stroke || head_stroke
            element(Svg::Polygon, points: shape.points, fill: colour,
                                  stroke: colour, stroke_width: head_width)
          end

          def text_fill(scene_text)
            scene_text.colour || painted(:"text_#{scene_text.role}") ||
              text_colour
          end

          def text_element(scene_text)
            element(Svg::Text, x: scene_text.x, y: scene_text.y,
                               content: scene_text.content,
                               text_anchor: scene_text.anchor,
                               fill: text_fill(scene_text),
                               font_family: text_family(scene_text),
                               font_size: text_size(scene_text),
                               font_style: text_font_style(scene_text),
                               font_weight: text_font_weight(scene_text))
              .tap { |text| Creole.assign(text, scene_text.content) }
          end

          def text_font_style(scene_text)
            scene_text.font_style || text_style(scene_text.role)
          end

          def text_font_weight(scene_text)
            scene_text.weight || text_weight(scene_text.role)
          end

          def text_family(scene_text)
            scene_text.family || font_family(scene_text.role)
          end

          def font_family(role = nil)
            return "monospace" if role == "warning"

            skin_family || theme_typography(:font_family) || "Arial"
          end

          def text_style(role)
            "italic" if role == "kind"
          end

          def text_weight(role)
            return "bold" if %w[fragment_tab box title].include?(role)

            "bold" if role == "fragment_guard" && skinned?
          end

          def text_size(scene_text)
            return scene_text.size.to_s if scene_text.size

            font_size(scene_text.role)
          end

          def font_size(role)
            return WARNING_SIZE if role == "warning"

            skinned = skin_size(role)
            return skinned if skinned

            normal = theme_typography(:font_size_normal) || 14
            return (normal.to_f * 0.85).to_s if role == "kind"

            normal.to_s
          end

          def note_fill
            painted(:note_fill) || skin_paint(:note_fill) ||
              theme_color(:note_fill)
          end

          def node_fill
            theme_color(:node_fill)
          end

          def node_stroke
            theme_color(:node_stroke)
          end

          def head_fill
            painted(:head_fill) || skin_paint(:head_fill) || node_fill
          end

          def head_stroke
            painted(:head_line) || skin_paint(:line) || node_stroke
          end

          def head_width
            skin_width(:thin) || stroke_width
          end

          def head_corner(shape_corner)
            skin_corner(shape_corner)
          end

          def edge_colour
            painted(:arrow) || skin_paint(:line) ||
              theme_color(:edge_stroke)
          end

          def text_colour
            theme_color(:label_text)
          end

          def stroke_width
            painted(:arrow_width) || skin_width(:arrow) ||
              (theme_shape(:stroke_width) || 2).to_s
          end
        end
      end
    end
  end
end
