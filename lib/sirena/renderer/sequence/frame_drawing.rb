# frozen_string_literal: true

module Sirena
  module Renderer
    class Sequence < Base
      # Draws the control frames and `box` groups of a laid-out sequence
      # diagram. Boxes go behind everything else; frames go behind the
      # messages they enclose.
      module FrameDrawing
        FRAME_STROKE = "#333333"
        TAB_FILL = "#eaeaea"
        DEFAULT_BOX_FILL = "none"
        DEFAULT_RECT_FILL = "#cccccc"
        FRAME_FONT_SIZE = "16"

        private

        def draw_boxes(scene, svg)
          scene.boxes.each_with_index do |box, index|
            group = Svg::Group.new.tap { |g| g.id = "box-#{index}" }
            group.children << box_outline(box)
            group.children << box_title(box) if box.title
            svg << group
          end
        end

        def box_outline(box)
          bounds_rect(box).tap do |rect|
            rect.fill = box.color || DEFAULT_BOX_FILL
            rect.stroke = "#000000"
            rect.stroke_opacity = "0.5"
            rect.class_name = "box"
          end
        end

        def box_title(box)
          frame_text(box.title, box.title_x, box.title_y)
        end

        def draw_frames(scene, svg)
          scene.frames.each_with_index do |frame, index|
            group = Svg::Group.new.tap { |g| g.id = "frame-#{index}" }
            fill_frame_group(group, frame)
            svg << group
          end
        end

        def fill_frame_group(group, frame)
          if frame.kind == "rect"
            group.children << rect_frame(frame)
            return
          end

          group.children << frame_outline(frame)
          group.children.concat(frame_tab(frame))
          group.children.concat(frame_dividers(frame))
        end

        def rect_frame(frame)
          bounds_rect(frame).tap do |rect|
            rect.fill = rect_fill(frame)
            rect.class_name = "frame-rect"
          end
        end

        def rect_fill(frame)
          frame.color.to_s.empty? ? DEFAULT_RECT_FILL : frame.color
        end

        def frame_outline(frame)
          bounds_rect(frame).tap do |rect|
            rect.fill = "none"
            rect.stroke = FRAME_STROKE
            rect.stroke_width = "2"
            rect.class_name = "frame-outline"
          end
        end

        def bounds_rect(shape)
          Svg::Rect.new.tap do |rect|
            rect.x = shape.x
            rect.y = shape.y
            rect.width = shape.width
            rect.height = shape.height
          end
        end

        def frame_tab(frame)
          tab = [frame_tab_polygon(frame),
                 frame_text(frame.kind, frame.kind_x, frame.kind_y)]
          return tab unless frame.title

          tab.concat(title_texts(frame))
        end

        def title_texts(frame)
          lines = frame.title_lines.empty? ? [frame.title] : frame.title_lines
          lines.zip(frame.title_ys).map do |line, y|
            frame_text(line, frame.title_x, y)
          end
        end

        def frame_tab_polygon(frame)
          Svg::Polygon.new.tap do |polygon|
            polygon.points = frame.tab_points
            polygon.fill = TAB_FILL
            polygon.stroke = FRAME_STROKE
          end
        end

        def frame_dividers(frame)
          frame.dividers.flat_map do |divider|
            [divider_line(divider),
             frame_text(divider.text, divider.text_x, divider.text_y)]
          end
        end

        def divider_line(divider)
          Svg::Line.new.tap do |line|
            line.x1 = divider.x1
            line.y1 = divider.y
            line.x2 = divider.x2
            line.y2 = divider.y
            style_divider(line)
          end
        end

        def style_divider(line)
          line.stroke = FRAME_STROKE
          line.stroke_width = "2"
          line.stroke_dasharray = "3,3"
        end

        def frame_text(content, horizontal, vertical)
          Svg::Text.new.tap do |text|
            text.x = horizontal
            text.y = vertical
            text.content = content
            text.fill = "#000000"
            text.font_family = "Arial, sans-serif"
            text.font_size = FRAME_FONT_SIZE
            text.text_anchor = "middle"
          end
        end
      end
    end
  end
end
