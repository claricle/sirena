# frozen_string_literal: true

require_relative "base"
require_relative "../layout/gantt"
require_relative "../svg/document"
require_relative "../svg/rect"
require_relative "../svg/text"
require_relative "../svg/line"
require_relative "../svg/polygon"

module Sirena
  module Renderer
    # Emits SVG from final, typed Gantt geometry.
    class Gantt < Base
      MARGIN_LEFT = Layout::Gantt::MARGIN_LEFT
      MARGIN_TOP = Layout::Gantt::MARGIN_TOP
      MARGIN_RIGHT = Layout::Gantt::MARGIN_RIGHT
      MARGIN_BOTTOM = Layout::Gantt::MARGIN_BOTTOM
      ROW_HEIGHT = Layout::Gantt::ROW_HEIGHT
      SECTION_HEIGHT = Layout::Gantt::SECTION_HEIGHT
      TASK_BAR_HEIGHT = Layout::Gantt::TASK_BAR_HEIGHT
      TIMELINE_WIDTH = Layout::Gantt::TIMELINE_WIDTH
      TIMELINE_HEIGHT = Layout::Gantt::TIMELINE_HEIGHT
      TITLE_Y = Layout::Gantt::TITLE_Y

      TASK_COLOR_ROLES = {
        done: :success,
        active: :info,
        critical: :error,
        default: :primary,
      }.freeze
      TASK_COLORS = begin
        colors = Theme::Registry.get(:default).colors
        TASK_COLOR_ROLES.transform_values { |role| colors.public_send(role) }
          .freeze
      end

      # @param scene [Layout::Gantt::Scene] final canvas geometry
      # @return [Svg::Document] rendered SVG document
      def render(scene)
        validate_scene!(scene)
        svg = create_document(scene)
        svg << text_element(scene.title) if scene.title
        render_timeline(scene.timeline, svg) if scene.timeline
        scene.sections.each { |section| render_section(section, svg) }
        svg
      end

      protected

      def validate_scene!(scene)
        return if scene.is_a?(Layout::Gantt::Scene)

        raise RenderError,
              "expected #{Layout::Gantt::Scene}, got #{scene.class}"
      end

      def render_timeline(timeline, svg)
        svg << timeline_background(timeline.background)
        timeline.labels.each { |label| svg << text_element(label) }
        timeline.grid_lines.each { |line| svg << grid_line(line) }
      end

      def timeline_background(geometry)
        Svg::Rect.new.tap do |rect|
          apply_rect_geometry(rect, geometry)
          rect.fill = theme_color(:node_fill)
          rect.stroke = theme_color(:node_stroke)
          rect.stroke_width = "1"
        end
      end

      def grid_line(geometry)
        Svg::Line.new.tap do |line|
          apply_line_geometry(line, geometry)
          apply_grid_line_style(line)
        end
      end

      def apply_line_geometry(line, geometry)
        line.x1 = geometry.x1
        line.y1 = geometry.y1
        line.x2 = geometry.x2
        line.y2 = geometry.y2
      end

      def apply_grid_line_style(line)
        line.stroke = theme_color(:node_stroke)
        line.stroke_width = "1"
        line.stroke_dasharray = "2,2"
      end

      def render_section(section, svg)
        svg << section_background(section.background)
        svg << text_element(section.label)
        section.tasks.each { |task| render_task(task, svg) }
      end

      def section_background(geometry)
        Svg::Rect.new.tap do |rect|
          apply_rect_geometry(rect, geometry)
          rect.fill = theme_color(:section_bg)
          rect.stroke = "none"
        end
      end

      def render_task(task, svg)
        svg << text_element(task.label)
        colour = theme_color(TASK_COLOR_ROLES.fetch(task.status.to_sym))
        render_task_shape(task, svg, colour)
      end

      def render_task_shape(task, svg, colour)
        if task.milestone_points
          return svg << milestone(task.milestone_points, colour)
        end
        return unless task.bar

        svg << task_bar(task.bar, colour)
        render_task_id(task.id_label, svg)
      end

      def render_task_id(label, svg)
        svg << text_element(label, fill: "#ffffff") if label
      end

      def task_bar(geometry, colour)
        Svg::Rect.new.tap do |rect|
          apply_rect_geometry(rect, geometry)
          rect.fill = colour
          rect.stroke = theme_color(:node_stroke)
          rect.stroke_width = "1"
          rect.rx = geometry.corner_radius
          rect.ry = geometry.corner_radius
        end
      end

      def milestone(points, colour)
        Svg::Polygon.new.tap do |polygon|
          polygon.points = points
          polygon.fill = colour
          polygon.stroke = theme_color(:node_stroke)
          polygon.stroke_width = "2"
        end
      end

      def apply_rect_geometry(rect, geometry)
        rect.x = geometry.x
        rect.y = geometry.y
        rect.width = geometry.width
        rect.height = geometry.height
      end

      def text_element(geometry, fill: nil)
        Svg::Text.new.tap do |text|
          apply_text_geometry(text, geometry)
          apply_text_style(text, geometry, fill)
        end
      end

      def apply_text_geometry(text, geometry)
        text.x = geometry.x
        text.y = geometry.y
        text.content = geometry.text
        text.text_anchor = geometry.text_anchor
        text.dominant_baseline = geometry.dominant_baseline
      end

      def apply_text_style(text, geometry, fill)
        text.fill = fill || theme_color(:label_text)
        text.font_family = theme_typography(:font_family) || "Arial, sans-serif"
        text.font_size = geometry.font_size.to_s
        text.font_weight = geometry.font_weight
      end
    end
  end
end
