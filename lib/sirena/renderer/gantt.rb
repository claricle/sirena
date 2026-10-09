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
      MAX_TIMELINE_LABELS = Layout::Gantt::MAX_TIMELINE_LABELS

      TASK_COLORS = {
        done: "#5CB85C",
        active: "#5BC0DE",
        critical: "#D9534F",
        default: "#428BCA",
      }.freeze

      # @param scene [Layout::Gantt::Scene] final canvas geometry
      # @return [Svg::Document] rendered SVG document
      def render(scene)
        svg = create_document_for_gantt(scene)
        svg << text_element(scene.title) if scene.title
        render_timeline(scene.timeline, svg) if scene.timeline
        scene.sections.each { |section| render_section(section, svg) }
        svg
      end

      protected

      def create_document_for_gantt(scene)
        Svg::Document.new.tap do |svg|
          svg.width = scene.width
          svg.height = scene.height
          svg.view_box = scene.view_box
        end
      end

      def render_timeline(timeline, svg)
        svg << timeline_background(timeline.background)
        timeline.labels.each { |label| svg << text_element(label) }
        timeline.grid_lines.each { |line| svg << grid_line(line) }
      end

      def timeline_background(geometry)
        Svg::Rect.new.tap do |rect|
          apply_rect_geometry(rect, geometry)
          rect.fill = theme_color(:node_fill) || "#f5f5f5"
          rect.stroke = theme_color(:node_stroke) || "#cccccc"
          rect.stroke_width = "1"
        end
      end

      def grid_line(geometry)
        Svg::Line.new.tap do |line|
          line.x1 = geometry.x1
          line.y1 = geometry.y1
          line.x2 = geometry.x2
          line.y2 = geometry.y2
          line.stroke = theme_color(:node_stroke) || "#e0e0e0"
          line.stroke_width = "1"
          line.stroke_dasharray = "2,2"
        end
      end

      def render_section(section, svg)
        svg << section_background(section.background)
        svg << text_element(section.label)
        section.tasks.each { |task| render_task(task, svg) }
      end

      def section_background(geometry)
        Svg::Rect.new.tap do |rect|
          apply_rect_geometry(rect, geometry)
          rect.fill = theme_color(:section_bg) || "#f0f0f0"
          rect.stroke = "none"
        end
      end

      def render_task(task, svg)
        svg << text_element(task.label)
        colour = TASK_COLORS.fetch(task.status.to_sym)
        if task.milestone_points
          svg << milestone(task.milestone_points, colour)
        elsif task.bar
          svg << task_bar(task.bar, colour)
          svg << text_element(task.id_label, fill: "#ffffff") if task.id_label
        end
      end

      def task_bar(geometry, colour)
        Svg::Rect.new.tap do |rect|
          apply_rect_geometry(rect, geometry)
          rect.fill = colour
          rect.stroke = theme_color(:node_stroke) || "#ffffff"
          rect.stroke_width = "1"
          rect.rx = geometry.corner_radius
          rect.ry = geometry.corner_radius
        end
      end

      def milestone(points, colour)
        Svg::Polygon.new.tap do |polygon|
          polygon.points = points
          polygon.fill = colour
          polygon.stroke = theme_color(:node_stroke) || "#ffffff"
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
          text.x = geometry.x
          text.y = geometry.y
          text.content = geometry.text
          text.fill = fill || theme_color(:label_text) || "#000000"
          text.font_family = theme_typography(:font_family) || "Arial, sans-serif"
          text.font_size = geometry.font_size.to_s
          text.text_anchor = geometry.text_anchor
          text.font_weight = geometry.font_weight
          text.dominant_baseline = geometry.dominant_baseline
        end
      end
    end
  end
end
