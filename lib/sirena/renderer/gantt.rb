# frozen_string_literal: true

require_relative "base"
require_relative "../svg/document"
require_relative "../svg/rect"
require_relative "../svg/text"
require_relative "../svg/line"
require_relative "../svg/path"
require_relative "../svg/group"
require_relative "../svg/polygon"

module Sirena
  module Renderer
    # Gantt chart renderer for converting Gantt diagrams to SVG.
    #
    # Converts a Gantt diagram model into SVG with timeline, tasks,
    # sections, and dependency indicators.
    #
    # @example Render a Gantt chart
    #   renderer = GanttRenderer.new
    #   svg = renderer.render(gantt_graph)
    class GanttRenderer < Base
      # Gantt chart dimensions
      MARGIN_LEFT = 200
      MARGIN_TOP = 80
      MARGIN_RIGHT = 50
      MARGIN_BOTTOM = 50
      ROW_HEIGHT = 40
      SECTION_HEIGHT = 30
      TASK_BAR_HEIGHT = 24
      TIMELINE_WIDTH = 800
      TIMELINE_HEIGHT = 40
      TITLE_Y = 40

      # Task status colors
      TASK_COLORS = {
        done: "#5CB85C",      # Green
        active: "#5BC0DE",    # Blue
        critical: "#D9534F", # Red
        default: "#428BCA"   # Default blue
      }.freeze

      # Renders a Gantt chart diagram to SVG.
      #
      # @param graph [Hash] the Gantt chart graph structure from transform
      # @return [Svg::Document] the rendered SVG document
      def render(graph)
        @graph = graph
        @current_y = MARGIN_TOP + TIMELINE_HEIGHT

        svg = create_document_for_gantt(graph)

        # Render title if present
        render_title(graph, svg) if graph[:title]

        # Render timeline axis
        render_timeline(graph, svg)

        # Render sections and tasks
        render_sections(graph, svg)

        svg
      end

      protected

      def create_document_for_gantt(graph)
        width = calculate_width_for_gantt(graph)
        height = calculate_height_for_gantt(graph)

        Svg::Document.new.tap do |doc|
          doc.width = width
          doc.height = height
          doc.view_box = "0 0 #{width} #{height}"
        end
      end

      def calculate_width_for_gantt(_graph)
        MARGIN_LEFT + TIMELINE_WIDTH + MARGIN_RIGHT
      end

      def calculate_height_for_gantt(graph)
        sections = graph[:sections] || []
        total_rows = sections.sum { |s| s[:tasks].length + 1 } # +1 for section header

        MARGIN_TOP + TIMELINE_HEIGHT + (total_rows * ROW_HEIGHT) + MARGIN_BOTTOM
      end

      def render_title(graph, svg)
        title_text = Svg::Text.new.tap do |t|
          t.x = MARGIN_LEFT + (TIMELINE_WIDTH / 2)
          t.y = TITLE_Y
          t.content = graph[:title]
          t.fill = theme_color(:label_text) || "#000000"
          t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
          t.font_size = (theme_typography(:font_size_large) || 18).to_s
          t.text_anchor = "middle"
          t.font_weight = "bold"
        end
        svg << title_text
      end

      def render_timeline(graph, svg)
        timeline = graph[:timeline]
        return unless timeline

        # Timeline background
        timeline_bg = Svg::Rect.new.tap do |r|
          r.x = MARGIN_LEFT
          r.y = MARGIN_TOP
          r.width = TIMELINE_WIDTH
          r.height = TIMELINE_HEIGHT
          r.fill = theme_color(:node_fill) || "#f5f5f5"
          r.stroke = theme_color(:node_stroke) || "#cccccc"
          r.stroke_width = "1"
        end
        svg << timeline_bg

        # Date labels
        render_date_labels(timeline, svg)

        # Grid lines (optional)
        render_grid_lines(timeline, svg)
      end

      def render_date_labels(timeline, svg)
        total_days = timeline[:total_days]
        return if total_days <= 0

        # Determine label interval based on timeline length
        interval = calculate_label_interval(total_days)

        (0..total_days).step(interval).each do |day|
          date = timeline[:start_date] + day
          x = MARGIN_LEFT + ((day.to_f / total_days) * TIMELINE_WIDTH)

          # Date label
          label = Svg::Text.new.tap do |t|
            t.x = x
            t.y = MARGIN_TOP + TIMELINE_HEIGHT - 10
            t.content = format_date(date, @graph[:axis_format])
            t.fill = theme_color(:label_text) || "#000000"
            t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
            t.font_size = (theme_typography(:font_size_small) || 10).to_s
            t.text_anchor = "middle"
          end
          svg << label
        end
      end

      def render_grid_lines(timeline, svg)
        total_days = timeline[:total_days]
        return if total_days <= 0

        interval = calculate_label_interval(total_days)
        sections = @graph[:sections] || []
        total_rows = sections.sum { |s| s[:tasks].length + 1 }
        grid_height = total_rows * ROW_HEIGHT

        (0..total_days).step(interval).each do |day|
          x = MARGIN_LEFT + ((day.to_f / total_days) * TIMELINE_WIDTH)

          line = Svg::Line.new.tap do |l|
            l.x1 = x
            l.y1 = MARGIN_TOP + TIMELINE_HEIGHT
            l.x2 = x
            l.y2 = MARGIN_TOP + TIMELINE_HEIGHT + grid_height
            l.stroke = theme_color(:node_stroke) || "#e0e0e0"
            l.stroke_width = "1"
            l.stroke_dasharray = "2,2"
          end
          svg << line
        end
      end

      def render_sections(graph, svg)
        sections = graph[:sections] || []

        sections.each do |section|
          render_section_header(section, svg)
          @current_y += SECTION_HEIGHT

          section[:tasks].each do |task|
            render_task(task, svg)
            @current_y += ROW_HEIGHT
          end
        end
      end

      def render_section_header(section, svg)
        # Section background
        section_bg = Svg::Rect.new.tap do |r|
          r.x = 0
          r.y = @current_y
          r.width = MARGIN_LEFT + TIMELINE_WIDTH + MARGIN_RIGHT
          r.height = SECTION_HEIGHT
          r.fill = theme_color(:section_bg) || "#f0f0f0"
          r.stroke = "none"
        end
        svg << section_bg

        # Section name
        section_text = Svg::Text.new.tap do |t|
          t.x = 10
          t.y = @current_y + (SECTION_HEIGHT / 2)
          t.content = section[:name]
          t.fill = theme_color(:label_text) || "#000000"
          t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
          t.font_size = (theme_typography(:font_size_base) || 14).to_s
          t.dominant_baseline = "middle"
          t.font_weight = "bold"
        end
        svg << section_text
      end

      def render_task(task, svg)
        # Task label
        task_label = Svg::Text.new.tap do |t|
          t.x = 10
          t.y = @current_y + (ROW_HEIGHT / 2)
          t.content = task[:description]
          t.fill = theme_color(:label_text) || "#000000"
          t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
          t.font_size = (theme_typography(:font_size_small) || 12).to_s
          t.dominant_baseline = "middle"
        end
        svg << task_label

        # Task bar (if dates are available)
        if task[:start_x] && task[:width]
          render_task_bar(task, svg)
        end
      end

      def render_task_bar(task, svg)
        x = MARGIN_LEFT + task[:start_x]
        y = @current_y + ((ROW_HEIGHT - TASK_BAR_HEIGHT) / 2)
        width = task[:width]

        # Handle milestone (zero duration)
        if task[:milestone] || width < 10
          render_milestone(x, y, task, svg)
        else
          render_normal_task(x, y, width, task, svg)
        end
      end

      def render_normal_task(x, y, width, task, svg)
        color = get_task_color(task)

        task_bar = Svg::Rect.new.tap do |r|
          r.x = x
          r.y = y
          r.width = width
          r.height = TASK_BAR_HEIGHT
          r.fill = color
          r.stroke = theme_color(:node_stroke) || "#ffffff"
          r.stroke_width = "1"
          r.rx = "3"
          r.ry = "3"
        end
        svg << task_bar

        # Add task ID if present
        if task[:id] && width > 40
          id_text = Svg::Text.new.tap do |t|
            t.x = x + (width / 2)
            t.y = y + (TASK_BAR_HEIGHT / 2)
            t.content = task[:id]
            t.fill = "#ffffff"
            t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
            t.font_size = "10"
            t.text_anchor = "middle"
            t.dominant_baseline = "middle"
          end
          svg << id_text
        end
      end

      def render_milestone(x, y, task, svg)
        # Render as diamond
        center_y = y + (TASK_BAR_HEIGHT / 2)
        size = 12

        points = [
          [x, center_y],               # Left
          [x + size, center_y - size], # Top
          [x + size * 2, center_y],    # Right
          [x + size, center_y + size]  # Bottom
        ]

        diamond = Svg::Polygon.new.tap do |p|
          p.points = points.map { |pt| "#{pt[0]},#{pt[1]}" }.join(" ")
          p.fill = get_task_color(task)
          p.stroke = theme_color(:node_stroke) || "#ffffff"
          p.stroke_width = "2"
        end
        svg << diamond
      end

      def get_task_color(task)
        return TASK_COLORS[:critical] if task[:critical]
        return TASK_COLORS[:done] if task[:done]
        return TASK_COLORS[:active] if task[:active]

        TASK_COLORS[:default]
      end

      def calculate_label_interval(total_days)
        return 1 if total_days <= 7
        return 7 if total_days <= 60
        return 14 if total_days <= 120

        30
      end

      def format_date(date, format)
        return date.strftime("%m-%d") unless format

        # Simple format conversion (extend as needed)
        format_str = format.gsub("%d", "%d")
                           .gsub("%m", "%m")
                           .gsub("%Y", "%Y")

        date.strftime(format_str)
      rescue StandardError
        date.strftime("%m-%d")
      end
    end
  end
end