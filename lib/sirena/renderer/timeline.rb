# frozen_string_literal: true

require_relative "base"
require_relative "../svg/document"
require_relative "../svg/rect"
require_relative "../svg/text"
require_relative "../svg/line"
require_relative "../svg/circle"
require_relative "../svg/group"

module Sirena
  module Renderer
    # Timeline renderer for converting timeline diagrams to SVG.
    #
    # Converts a Timeline diagram model into SVG with horizontal axis,
    # event markers, descriptions, and optional section grouping.
    #
    # @example Render a timeline
    #   renderer = TimelineRenderer.new
    #   svg = renderer.render(timeline_graph)
    class TimelineRenderer < Base
      # Timeline dimensions
      MARGIN_LEFT = 80
      MARGIN_TOP = 100
      MARGIN_RIGHT = 80
      MARGIN_BOTTOM = 60
      TIMELINE_WIDTH = 800
      TIMELINE_HEIGHT = 6
      EVENT_MARKER_RADIUS = 8
      EVENT_LABEL_OFFSET_Y = 35
      SECTION_HEIGHT = 40
      SECTION_SPACING = 20
      TITLE_Y = 40

      # Section colors (cycle through for visual distinction)
      SECTION_COLORS = [
        "#4472C4", # Blue
        "#ED7D31", # Orange
        "#A5A5A5", # Gray
        "#FFC000", # Yellow
        "#5B9BD5", # Light Blue
        "#70AD47"  # Green
      ].freeze

      # Renders a timeline diagram to SVG.
      #
      # @param graph [Hash] the timeline graph structure from transform
      # @return [Svg::Document] the rendered SVG document
      def render(graph)
        @graph = graph
        @current_y = MARGIN_TOP

        svg = create_document_for_timeline(graph)

        # Render title if present
        render_title(graph, svg) if graph[:title]

        # Render sections or single timeline
        if graph[:metadata][:has_sections]
          render_sections_timeline(graph, svg)
        else
          render_simple_timeline(graph, svg)
        end

        svg
      end

      protected

      def create_document_for_timeline(graph)
        width = calculate_width_for_timeline(graph)
        height = calculate_height_for_timeline(graph)

        Svg::Document.new.tap do |doc|
          doc.width = width
          doc.height = height
          doc.view_box = "0 0 #{width} #{height}"
        end
      end

      def calculate_width_for_timeline(_graph)
        MARGIN_LEFT + TIMELINE_WIDTH + MARGIN_RIGHT
      end

      def calculate_height_for_timeline(graph)
        base_height = MARGIN_TOP + MARGIN_BOTTOM + 100

        if graph[:metadata][:has_sections]
          section_count = graph[:sections].length
          base_height += section_count * (SECTION_HEIGHT + SECTION_SPACING)
        end

        base_height
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

      def render_simple_timeline(graph, svg)
        # Render timeline axis
        render_timeline_axis(svg, @current_y)

        # Render events
        events = graph[:events] || []
        render_events(events, svg, @current_y, 0)

        # Render time labels
        render_time_labels(graph[:timeline], svg, @current_y)
      end

      def render_sections_timeline(graph, svg)
        sections = graph[:sections] || []

        sections.each_with_index do |section, index|
          # Section header
          render_section_header(section, svg, @current_y, index)
          @current_y += SECTION_HEIGHT

          # Render timeline axis for this section
          render_timeline_axis(svg, @current_y)

          # Render events or tasks
          if section[:has_events]
            render_events(section[:events], svg, @current_y, index)
          elsif section[:has_tasks]
            render_tasks(section[:tasks], svg, @current_y, index)
          end

          # Render time labels (only for first section)
          if index.zero?
            render_time_labels(graph[:timeline], svg, @current_y)
          end

          @current_y += SECTION_SPACING
        end
      end

      def render_section_header(section, svg, y, index)
        color = SECTION_COLORS[index % SECTION_COLORS.length]

        # Section label
        section_text = Svg::Text.new.tap do |t|
          t.x = MARGIN_LEFT
          t.y = y
          t.content = section[:name]
          t.fill = color
          t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
          t.font_size = (theme_typography(:font_size_base) || 14).to_s
          t.font_weight = "bold"
        end
        svg << section_text
      end

      def render_timeline_axis(svg, y)
        axis_line = Svg::Rect.new.tap do |r|
          r.x = MARGIN_LEFT
          r.y = y
          r.width = TIMELINE_WIDTH
          r.height = TIMELINE_HEIGHT
          r.fill = theme_color(:node_fill) || "#cccccc"
          r.stroke = "none"
          r.rx = TIMELINE_HEIGHT / 2
          r.ry = TIMELINE_HEIGHT / 2
        end
        svg << axis_line
      end

      def render_events(events, svg, y, section_index)
        color = SECTION_COLORS[section_index % SECTION_COLORS.length]

        events.each do |event|
          x = calculate_event_x(event[:x_position])

          # Event marker (circle)
          marker = Svg::Circle.new.tap do |c|
            c.cx = x
            c.cy = y + (TIMELINE_HEIGHT / 2)
            c.r = EVENT_MARKER_RADIUS
            c.fill = color
            c.stroke = theme_color(:node_stroke) || "#ffffff"
            c.stroke_width = "2"
          end
          svg << marker

          # Event descriptions
          render_event_descriptions(event, x, y, svg)
        end
      end

      def render_event_descriptions(event, x, y, svg)
        descriptions = event[:descriptions] || []

        descriptions.each_with_index do |desc, idx|
          label_y = y + EVENT_LABEL_OFFSET_Y + (idx * 16)

          desc_text = Svg::Text.new.tap do |t|
            t.x = x
            t.y = label_y
            t.content = desc.to_s.strip
            t.fill = theme_color(:label_text) || "#000000"
            t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
            t.font_size = (theme_typography(:font_size_small) || 11).to_s
            t.text_anchor = "middle"
          end
          svg << desc_text
        end

        # Event time label (above marker)
        time_label = Svg::Text.new.tap do |t|
          t.x = x
          t.y = y - 15
          t.content = event[:time].to_s
          t.fill = theme_color(:label_text) || "#666666"
          t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
          t.font_size = (theme_typography(:font_size_small) || 10).to_s
          t.text_anchor = "middle"
          t.font_weight = "bold"
        end
        svg << time_label
      end

      def render_tasks(tasks, svg, y, section_index)
        # For sections with tasks (no timestamps), distribute evenly
        return if tasks.empty?

        color = SECTION_COLORS[section_index % SECTION_COLORS.length]
        spacing = TIMELINE_WIDTH / (tasks.length + 1).to_f

        tasks.each_with_index do |task, index|
          x = MARGIN_LEFT + (spacing * (index + 1))

          # Task marker
          marker = Svg::Circle.new.tap do |c|
            c.cx = x
            c.cy = y + (TIMELINE_HEIGHT / 2)
            c.r = EVENT_MARKER_RADIUS
            c.fill = color
            c.stroke = theme_color(:node_stroke) || "#ffffff"
            c.stroke_width = "2"
          end
          svg << marker

          # Task label
          task_text = Svg::Text.new.tap do |t|
            t.x = x
            t.y = y + EVENT_LABEL_OFFSET_Y
            t.content = task.to_s
            t.fill = theme_color(:label_text) || "#000000"
            t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
            t.font_size = (theme_typography(:font_size_small) || 11).to_s
            t.text_anchor = "middle"
          end
          svg << task_text
        end
      end

      def render_time_labels(timeline, svg, y)
        return unless timeline

        min_time = timeline[:min]
        max_time = timeline[:max]

        # Render min and max labels
        render_time_label(min_time.to_s, MARGIN_LEFT, y + TIMELINE_HEIGHT + 20, svg)
        render_time_label(max_time.to_s, MARGIN_LEFT + TIMELINE_WIDTH,
                         y + TIMELINE_HEIGHT + 20, svg)

        # Optional: render mid-point
        mid_time = ((min_time + max_time) / 2.0).round
        render_time_label(mid_time.to_s, MARGIN_LEFT + (TIMELINE_WIDTH / 2),
                         y + TIMELINE_HEIGHT + 20, svg)
      end

      def render_time_label(label, x, y, svg)
        time_text = Svg::Text.new.tap do |t|
          t.x = x
          t.y = y
          t.content = label
          t.fill = theme_color(:label_text) || "#666666"
          t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
          t.font_size = (theme_typography(:font_size_small) || 10).to_s
          t.text_anchor = "middle"
        end
        svg << time_text
      end

      def calculate_event_x(x_position)
        # x_position is a percentage (0-100) from transform
        MARGIN_LEFT + ((x_position / 100.0) * TIMELINE_WIDTH)
      end
    end
  end
end