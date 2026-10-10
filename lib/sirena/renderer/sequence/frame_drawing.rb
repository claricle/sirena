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
        TAB_SLANT = 8
        TAB_HEIGHT = 20
        DEFAULT_BOX_FILL = "none"
        DEFAULT_RECT_FILL = "#cccccc"
        FRAME_FONT_SIZE = "14"

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
          Svg::Rect.new.tap do |rect|
            rect.x = box.x
            rect.y = box.y
            rect.width = box.width
            rect.height = box.height
            rect.fill = box.color || DEFAULT_BOX_FILL
            rect.stroke = "#000000"
            rect.stroke_opacity = "0.5"
            rect.class_name = "box"
          end
        end

        def box_title(box)
          frame_text(box.title, box.x + (box.width / 2), box.title_y)
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
          frame_rectangle(frame).tap do |rect|
            rect.fill = rect_fill(frame)
            rect.class_name = "frame-rect"
          end
        end

        def rect_fill(frame)
          frame.color.to_s.empty? ? DEFAULT_RECT_FILL : frame.color
        end

        def frame_outline(frame)
          frame_rectangle(frame).tap do |rect|
            rect.fill = "none"
            rect.stroke = FRAME_STROKE
            rect.stroke_width = "2"
            rect.class_name = "frame-outline"
          end
        end

        def frame_rectangle(frame)
          Svg::Rect.new.tap do |rect|
            rect.x = frame.x
            rect.y = frame.y
            rect.width = frame.width
            rect.height = frame.height
          end
        end

        def frame_tab(frame)
          tab = [frame_tab_polygon(frame),
                 frame_text(frame.kind, frame.x + (frame.tab_width / 2),
                            frame.y + 14)]
          return tab unless frame.title

          rest = frame.width - frame.tab_width
          center = frame.x + frame.tab_width + (rest / 2)
          tab << frame_text(frame.title, center, frame.y + 18)
        end

        def frame_tab_polygon(frame)
          left = frame.x
          right = left + frame.tab_width
          top = frame.y
          Svg::Polygon.new.tap do |polygon|
            polygon.points = "#{left},#{top} #{right},#{top} " \
                             "#{right},#{top + 13} " \
                             "#{right - TAB_SLANT},#{top + TAB_HEIGHT} " \
                             "#{left},#{top + TAB_HEIGHT}"
            polygon.fill = TAB_FILL
            polygon.stroke = FRAME_STROKE
          end
        end

        def frame_dividers(frame)
          center = frame.x + (frame.width / 2)
          frame.dividers.flat_map do |divider|
            [divider_line(frame, divider),
             frame_text(divider.text, center, divider.text_y)]
          end
        end

        def divider_line(frame, divider)
          Svg::Line.new.tap do |line|
            line.x1 = frame.x
            line.y1 = divider.y
            line.x2 = frame.x + frame.width
            line.y2 = divider.y
            line.stroke = FRAME_STROKE
            line.stroke_width = "2"
            line.stroke_dasharray = "3,3"
          end
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
