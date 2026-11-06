# frozen_string_literal: true

require_relative "../../renderer/base"
require_relative "../../svg"
require_relative "scene"
require_relative "style"
require_relative "creole"
require_relative "note_outline"
require_relative "class_header"
require_relative "member_icon_elements"

module Sirena
  module Notation
    module PlantUML
      # Draws a PlantUML Scene without changing any of its geometry.
      class Renderer < Sirena::Renderer::Base
        CREOLE_ROLES = %w[note relation_label member_note].freeze
        BOLD_ROLES = %w[package_title].freeze
        # PlantUML draws a compartment rule hairline-thin and one pixel
        # short of the box's border on each side.
        RULE_INSET = 1.0
        RULE_WIDTH = "0.5"
        private_constant :BOLD_ROLES, :CREOLE_ROLES, :RULE_INSET, :RULE_WIDTH

        # @param style [Style::Sheet] how the diagram's source styles it;
        #   only what the source sets overrides the theme
        def initialize(theme: nil, style: Style::Sheet.new)
          super(theme: theme)
          @style = style
        end

        def render(scene)
          document = blank_document(scene)
          render_background(scene, document)
          render_content(scene, content_target(scene, document))
          scene.panels.to_a.each { |panel| render_panel(panel, document) }
          document
        end

        private

        def render_content(scene, content)
          scene.frames.each { |frame| render_frame(frame, content) }
          scene.relations.each { |relation| render_relation(relation, content) }
          scene.boxes.each do |box|
            @box = box
            render_box(box, content)
          end
        end

        def render_background(scene, document)
          return unless scene.background

          document << Svg::Rect.new(x: 0, y: 0, width: scene.width,
                                    height: scene.height,
                                    fill: scene.background)
        end

        # The diagram moves as one when captions make room around it.
        def content_target(scene, document)
          return document if scene.panels.to_a.empty?

          group = Svg::Group.new(
            transform: "translate(#{scene.content_x}, #{scene.content_y})",
          )
          document << group
          group
        end

        def render_panel(panel, document)
          group = Svg::Group.new(id: panel.id)
          group << panel_rectangle(panel) if panel.fill || panel.bordered
          group << panel_text(panel)
          document << group
        end

        def panel_rectangle(panel)
          rect = Svg::Rect.new(x: panel.x, y: panel.y, width: panel.width,
                               height: panel.height,
                               fill: panel.fill || "none")
          border_panel(rect) if panel.bordered
          rect
        end

        def border_panel(rect)
          rect.rx = 7.5
          rect.ry = 7.5
          rect.stroke = "#000000"
          rect.stroke_width = "1"
        end

        def panel_text(panel)
          Svg::Text.new.tap do |text|
            text.x = panel.x + (panel.width / 2)
            text.y = panel.y + 5.0 + (panel.font_size * 0.95)
            style_panel_text(text, panel)
          end
        end

        def style_panel_text(text, panel)
          text.content = panel.content
          text.text_anchor = "middle"
          text.fill = panel.colour || text_colour
          text.font_family = font_family
          text.font_size = panel.font_size.to_s
          text.font_weight = "bold" if panel.bold
        end

        def blank_document(scene)
          Svg::Document.new(
            width: scene.width,
            height: scene.height,
            view_box: "0 0 #{scene.width} #{scene.height}",
          )
        end

        def render_frame(frame, document)
          group = Svg::Group.new(id: frame.id)
          frame_shapes(frame).each { |shape| group << shape }
          frame.texts.each { |text| group << text_element(text) }
          document << group
        end

        def frame_shapes(frame)
          [frame_body(frame),
           (frame_tab(frame) if frame.tab_width),
           (package_icon(frame) if frame.icon)].compact
        end

        def frame_body(frame)
          frame_rectangle(frame, frame.width, frame.height, frame.fill)
        end

        # A folder's tab sits on top of the body; a frame has none.
        def frame_tab(frame)
          frame_rectangle(frame, frame.tab_width, 22.0, frame.fill)
        end

        def frame_rectangle(frame, width, height, fill)
          Svg::Rect.new(x: frame.x, y: frame.y, width: width, height: height,
                        fill: fill || "none", stroke: node_stroke,
                        stroke_width: node_width)
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
          relation_marker_elements(relation).each { |e| group << e }
          relation_text_elements(relation).each { |e| group << e }
          document << group
          render_junction_dots(relation, document)
        end

        def relation_text_elements(relation)
          relation.texts.map { |text| text_element(text) } +
            relation.qualifiers.flat_map { |box| qualifier_elements(box) }
        end

        def qualifier_elements(box)
          rect = Svg::Rect.new(x: box.x, y: box.y, width: box.width,
                               height: box.height, fill: node_fill,
                               stroke: node_stroke, stroke_width: node_width)
          [rect, *box.texts.map { |text| text_element(text) }]
        end

        # The dot sits in a group of its own, apart from the relation's.
        def render_junction_dots(relation, document)
          relation.markers.select { |marker| marker.shape == "dot" }
            .each_with_index do |marker, number|
            dot = Svg::Group.new(id: "dot-#{relation.id}-#{number}")
            dot << junction_dot(marker)
            document << dot
          end
        end

        def relation_line(relation)
          Svg::Path.new.tap do |path|
            path.d = relation.path
            path.fill = "none"
            path.stroke_dasharray = relation_dashing(relation)
            relation_ink(path, relation)
          end
        end

        def relation_ink(element, relation)
          element.stroke = relation.stroke || edge_colour
          element.stroke_width = relation.stroke_width&.to_s || stroke_width
        end

        def relation_dashing(relation)
          return "2,3" if relation.dotted

          "6,4" if relation.dashed
        end

        def relation_marker_elements(relation)
          relation.markers.flat_map { |marker| marker_elements(marker) }
            .each { |element| restyle(element, relation) }
        end

        # A marker takes its relation's own colour and thickness.
        def restyle(element, relation)
          return unless relation.stroke || relation.stroke_width

          relation_ink(element, relation)
          thick = relation.stroke_width.to_f > 4.0
          element.stroke_width = "1" if thick
          element.fill = relation.stroke if recoloured?(element, relation,
                                                        thick)
        end

        def recoloured?(element, relation, thick)
          relation.stroke && (thick || element.fill == edge_colour)
        end

        def marker_elements(marker)
          return [] if marker.shape == "dot"
          return [relation_marker(marker)] unless marker.shape == "nesting"

          [nesting_circle(marker), nesting_cross(marker)]
        end

        def junction_dot(marker)
          Svg::Circle.new(cx: marker.cx, cy: marker.cy, r: marker.r,
                          fill: edge_colour, stroke: edge_colour,
                          stroke_width: stroke_width)
        end

        def nesting_circle(marker)
          Svg::Circle.new.tap do |circle|
            circle.cx = marker.cx
            circle.cy = marker.cy
            circle.r = marker.r
            circle.fill = node_fill
            edge_stroke(circle)
          end
        end

        def edge_stroke(element)
          element.stroke = edge_colour
          element.stroke_width = stroke_width
        end

        def nesting_cross(marker)
          Svg::Path.new.tap do |path|
            path.d = marker.cross
            path.fill = "none"
            edge_stroke(path)
          end
        end

        def relation_marker(marker)
          Svg::Polygon.new.tap do |polygon|
            polygon.points = marker.points
            polygon.fill = marker.filled ? edge_colour : node_fill
            polygon.stroke = edge_colour
            polygon.stroke_width = stroke_width
          end
        end

        def render_box(box, document)
          group = Svg::Group.new(id: box_id(box))
          [box_rectangle(box), *spot_elements(box), *rule_lines(box)]
            .each { |element| group << element }
          box.texts.each { |text| add_text(group, text) }
          document << group
        end

        def add_text(group, text)
          group << MemberIconElements.group(text.icon) if text.icon
          group << text_element(text)
        end

        def rule_lines(box)
          return [] if box.kind.end_with?("note")

          box.separators.map { |separator| separator_line(separator) }
        end

        def spot_elements(box)
          spot = box.spot
          return [] unless spot

          glyph = ClassHeader.glyph(spot.kind.to_sym)
          [Svg::Circle.new(cx: spot.cx, cy: spot.cy, r: ClassHeader::RADIUS,
                           fill: glyph.fill, stroke: node_stroke,
                           stroke_width: "1"),
           Svg::Path.new(d: translate_outline(glyph.outline, spot),
                         fill: "#000000")]
        end

        def translate_outline(outline, spot)
          outline.gsub(/(-?[\d.]+),(-?[\d.]+)/) do
            "#{format('%g', ($1.to_f + spot.cx).round(4))}," \
              "#{format('%g', ($2.to_f + spot.cy).round(4))}"
          end
        end

        def box_id(box)
          box.kind.end_with?("note") ? box.id : "class-#{box.id}"
        end

        def box_rectangle(box)
          return member_note_shape(box) if box.kind == "member_note"
          return note_shape(box) if box.kind == "note"

          Svg::Rect.new.tap do |rectangle|
            apply_box_geometry(rectangle, box)
            apply_box_style(rectangle)
          end
        end

        # A note: a folded top right corner and, when it points at a class,
        # a tail on the edge that faces it.
        def note_shape(box)
          Svg::Path.new(d: NoteOutline.call(box), fill: note_fill(box),
                        stroke: node_stroke, stroke_width: node_width)
        end

        def member_note_shape(box)
          outline = [*member_note_near_edge(box), *member_note_far_edge(box),
                     "Z"].join(" ")
          Svg::Path.new(d: outline, fill: note_fill(box), stroke: node_stroke,
                        stroke_width: node_width)
        end

        def member_note_near_edge(box)
          pointer = box.separators.first
          left = box.x
          top = box.y
          middle = top + (box.height / 2)
          ["M #{left} #{top}", "L #{left} #{middle - 4}",
           "L #{pointer.x1} #{pointer.y1}", "L #{left} #{middle + 4}",
           "L #{left} #{top + box.height}"]
        end

        def member_note_far_edge(box)
          right = box.x + box.width
          fold = 10.0
          ["L #{right} #{box.y + box.height}", "L #{right} #{box.y + fold}",
           "L #{right - fold} #{box.y}"]
        end

        def apply_box_geometry(rectangle, box)
          rectangle.x = box.x
          rectangle.y = box.y
          rectangle.width = box.width
          rectangle.height = box.height
          rectangle.rx = rectangle.ry = box_look(:round_corner)
        end

        def apply_box_style(rectangle)
          rectangle.fill = box_look(:background)
          rectangle.stroke = box_look(:border)
          rectangle.stroke_width = box_look(:line_thickness).to_s
          dash = box_look(:line_style)
          rectangle.stroke_dasharray = dash if dash
        end

        # What the source says of the class being drawn, else PlantUML's own
        # default look.
        def box_look(property)
          id = @box&.id
          @style.resolve(:class, property, id: id,
                                           stereotype: stereotype_of(id))
        end

        def stereotype_of(id)
          @style.element(id)[:stereotype]
        end

        # `#yellow` is a colour name and `#FFAA00` a hex value.
        def note_fill(box)
          colour = box.fill&.delete_prefix("#")
          return "#FEFFDD" unless colour
          return "##{colour}" if colour.match?(/\A\h{3}(?:\h{3})?\z/)

          colour
        end

        def separator_line(segment)
          Svg::Line.new(x1: segment.x1 + RULE_INSET, y1: segment.y1,
                        x2: segment.x2 - RULE_INSET, y2: segment.y2,
                        stroke: node_stroke,
                        stroke_width: (segment.width || RULE_WIDTH).to_s,
                        stroke_dasharray: segment.dash)
        end

        def text_element(scene_text)
          Svg::Text.new.tap do |text|
            apply_text_geometry(text, scene_text)
            apply_text_style(text, scene_text.role)
            apply_creole(text, scene_text)
          end
        end

        def apply_creole(text, scene_text)
          return unless CREOLE_ROLES.include?(scene_text.role)

          Creole.assign(text, scene_text.content)
        end

        def apply_text_geometry(text, scene_text)
          text.x = scene_text.x
          text.y = scene_text.y
          text.content = scene_text.content
          text.text_anchor = scene_text.anchor
        end

        def apply_text_style(text, role)
          text.fill = box_look(:font_colour)
          text.font_family = font_family
          text.font_size = font_size(role)
          text.font_weight = "bold" if BOLD_ROLES.include?(role)
          text.font_style = "italic" if italic?(role)
        end

        ITALIC_SPOTS = %w[abstract interface].freeze
        private_constant :ITALIC_SPOTS

        def italic?(role)
          return true if %w[kind member_abstract].include?(role)

          role == "class_name" && ITALIC_SPOTS.include?(@box&.spot&.kind)
        end

        def font_family
          written = @style.explicit(:class, :font_name)
          return written if written

          box_look(:font_name)
        end

        def font_size(role)
          normal = theme_typography(:font_size_normal) || 14
          return (normal.to_f * (13.0 / 14.0)).to_s if role == "member_note"
          return (normal.to_f * 0.85).to_s if role == "kind"

          small_roles = %w[multiplicity relation_label]
          return (normal.to_f * 0.9).to_s if small_roles.include?(role)

          normal.to_s
        end

        def node_fill
          @style.resolve(:class, :background)
        end

        def node_stroke
          @style.resolve(:class, :border)
        end

        def edge_colour
          @style.resolve(:arrow, :border)
        end

        def text_colour
          @style.resolve(:any, :font_colour)
        end

        def node_width
          @style.resolve(:class, :line_thickness).to_s
        end

        def stroke_width
          @style.resolve(:arrow, :line_thickness).to_s
        end
      end
    end
  end
end
