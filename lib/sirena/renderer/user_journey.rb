# frozen_string_literal: true

require_relative "base"
require_relative "../layout/user_journey"

module Sirena
  module Renderer
    # User Journey diagram renderer for converting graphs to SVG.
    #
    # Converts a laid-out graph structure (with computed positions) into
    # SVG using the Svg builder classes. Handles journey title, section
    # swimlanes, task boxes with score-based colors, actor lists, and
    # sequential timeline flow.
    #
    # @example Render a user journey
    #   renderer = UserJourney.new
    #   svg = renderer.render(laid_out_graph)
    class UserJourney < Base
      # Font size for title
      TITLE_FONT_SIZE = 20

      # Font size for section headers
      SECTION_FONT_SIZE = 16

      # Font size for task names
      TASK_NAME_FONT_SIZE = 14

      # Font size for score
      SCORE_FONT_SIZE = 18

      # Font size for actors
      ACTOR_FONT_SIZE = 11

      # Padding for various elements
      TITLE_PADDING = 20
      SECTION_PADDING = 10
      TASK_PADDING = 10

      # Score-based color mapping
      SCORE_COLORS = {
        red: "#ff6b6b",
        yellow: "#feca57",
        green: "#48dbfb",
      }.freeze

      SCORE_COLOR_ROLES = {
        red: :error,
        yellow: :warning,
        green: :success,
      }.freeze

      # Renders a laid-out graph to SVG.
      #
      # @param graph [Hash] laid-out graph with node positions
      # @return [Svg::Document] the rendered SVG document
      def render(graph)
        scene = typed_scene(graph)
        svg = create_document(scene)
        render_scene_title(svg, scene)
        scene.sections.each { |label| svg << label_element(label) }
        scene.tasks.each { |task| render_typed_task(svg, task) }
        scene.arrows.each { |arrow| render_typed_arrow(arrow, svg) }
        svg
      end

      protected

      def calculate_width(graph)
        return 800 unless graph[:children]

        max_x = graph[:children].map do |node|
          (node[:x] || 0) + (node[:width] || 120)
        end.max || 800

        max_x + 40
      end

      def calculate_height(graph)
        return 600 unless graph[:children]

        max_y = graph[:children].map do |node|
          (node[:y] || 0) + (node[:height] || 80)
        end.max || 600

        # Add space for title and sections
        metadata = graph[:metadata] || {}
        title_height = if metadata[:title]
                         TITLE_FONT_SIZE +
                           TITLE_PADDING * 2
                       else
                         0
                       end
        max_y + title_height + 60
      end

      def render_title(svg, title, y_pos)
        text = Svg::Text.new.tap do |t|
          t.x = 20
          t.y = y_pos + TITLE_FONT_SIZE
          t.content = title
          t.fill = "#000000"
          t.font_family = "Arial, sans-serif"
          t.font_size = TITLE_FONT_SIZE.to_s
          t.font_weight = "bold"
        end
        svg << text

        y_pos + TITLE_FONT_SIZE + TITLE_PADDING
      end

      def render_sections_and_tasks(svg, graph, start_y)
        return start_y unless graph[:children]

        # Group tasks by section
        sections = group_tasks_by_section(graph[:children])

        current_y = start_y

        sections.each do |section_name, tasks|
          # Render section header
          current_y = render_section_header(svg, section_name, current_y)

          # Render tasks in this section
          tasks.each do |task|
            render_task(svg, task)
          end

          current_y += 20
        end

        current_y
      end

      def group_tasks_by_section(nodes)
        grouped = {}

        nodes.each do |node|
          metadata = node[:metadata] || {}
          section_name = metadata[:section_name] || "Default"

          grouped[section_name] ||= []
          grouped[section_name] << node
        end

        grouped
      end

      def render_section_header(svg, section_name, y_pos)
        text = Svg::Text.new.tap do |t|
          t.x = 20
          t.y = y_pos + SECTION_FONT_SIZE
          t.content = section_name
          t.fill = "#666666"
          t.font_family = "Arial, sans-serif"
          t.font_size = SECTION_FONT_SIZE.to_s
          t.font_weight = "bold"
        end
        svg << text

        y_pos + SECTION_FONT_SIZE + SECTION_PADDING
      end

      def render_task(svg, node)
        x = node[:x] || 0
        y = node[:y] || 0
        width = node[:width] || 120
        height = node[:height] || 80

        metadata = node[:metadata] || {}
        score_color = metadata[:score_color] || :yellow

        # Create group for the task
        group = Svg::Group.new.tap do |g|
          g.id = "task-#{node[:id]}"
        end

        # Render task box with score-based color
        box = Svg::Rect.new.tap do |r|
          r.x = x
          r.y = y
          r.width = width
          r.height = height
          r.fill = SCORE_COLORS[score_color]
          r.stroke = "#333333"
          r.stroke_width = "2"
          r.rx = "5"
          r.ry = "5"
        end
        group.children << box

        # Render task content
        render_task_content(node, metadata, group)

        svg << group
      end

      def render_task_content(node, metadata, group)
        x = node[:x] || 0
        y = node[:y] || 0
        width = node[:width] || 120
        node[:height] || 80

        current_y = y + TASK_PADDING

        # Render task name at top
        name = metadata[:name] || "Task"
        name_text = Svg::Text.new.tap do |t|
          t.x = x + width / 2
          t.y = current_y + TASK_NAME_FONT_SIZE
          t.content = name
          t.fill = "#000000"
          t.font_family = "Arial, sans-serif"
          t.font_size = TASK_NAME_FONT_SIZE.to_s
          t.text_anchor = "middle"
          t.font_weight = "bold"
        end
        group.children << name_text

        current_y += TASK_NAME_FONT_SIZE + 10

        # Render score in center
        score = metadata[:score] || 3
        score_text = Svg::Text.new.tap do |t|
          t.x = x + width / 2
          t.y = current_y + SCORE_FONT_SIZE
          t.content = score.to_s
          t.fill = "#000000"
          t.font_family = "Arial, sans-serif"
          t.font_size = SCORE_FONT_SIZE.to_s
          t.text_anchor = "middle"
          t.font_weight = "bold"
        end
        group.children << score_text

        current_y += SCORE_FONT_SIZE + 10

        # Render actors at bottom
        actors = metadata[:actors] || []
        actors_text = actors.join(", ")
        actor_text = Svg::Text.new.tap do |t|
          t.x = x + width / 2
          t.y = current_y + ACTOR_FONT_SIZE
          t.content = actors_text
          t.fill = "#333333"
          t.font_family = "Arial, sans-serif"
          t.font_size = ACTOR_FONT_SIZE.to_s
          t.text_anchor = "middle"
        end
        group.children << actor_text
      end

      def render_timeline(graph, svg)
        return unless graph[:edges]

        graph[:edges].each do |edge|
          render_timeline_arrow(edge, graph, svg)
        end
      end

      def render_timeline_arrow(edge, graph, svg)
        source = find_node(graph, edge[:sources]&.first)
        target = find_node(graph, edge[:targets]&.first)

        return unless source && target

        # Create arrow group
        group = Svg::Group.new.tap do |g|
          g.id = "arrow-#{edge[:id]}"
        end

        # Calculate connection points (right side of source to
        # left side of target)
        from_x = (source[:x] || 0) + (source[:width] || 120)
        from_y = (source[:y] || 0) + (source[:height] || 80) / 2
        to_x = target[:x] || 0
        to_y = (target[:y] || 0) + (target[:height] || 80) / 2

        # Render line
        line = Svg::Line.new.tap do |l|
          l.x1 = from_x
          l.y1 = from_y
          l.x2 = to_x
          l.y2 = to_y
          l.stroke = "#666666"
          l.stroke_width = "2"
        end
        group.children << line

        # Render arrowhead
        render_arrowhead(to_x, to_y, from_x, from_y, group)

        svg << group
      end

      def render_arrowhead(to_x, to_y, from_x, from_y, group)
        # Calculate angle
        dx = to_x - from_x
        dy = to_y - from_y
        angle = Math.atan2(dy, dx)

        # Arrow size
        arrow_length = 10

        # Calculate arrowhead points
        point1_x = to_x - arrow_length * Math.cos(angle - Math::PI / 6)
        point1_y = to_y - arrow_length * Math.sin(angle - Math::PI / 6)
        point2_x = to_x - arrow_length * Math.cos(angle + Math::PI / 6)
        point2_y = to_y - arrow_length * Math.sin(angle + Math::PI / 6)

        # Create arrowhead path
        path_d = "M #{to_x},#{to_y} L #{point1_x},#{point1_y} " \
                 "M #{to_x},#{to_y} L #{point2_x},#{point2_y}"

        path = Svg::Path.new.tap do |p|
          p.d = path_d
          p.stroke = "#666666"
          p.stroke_width = "2"
          p.fill = "none"
        end
        group.children << path
      end

      def find_node(graph, node_id)
        return nil unless graph[:children] && node_id

        graph[:children].find { |n| n[:id] == node_id }
      end

      def typed_scene(graph)
        return graph if graph.is_a?(Layout::UserJourney::Scene)

        Layout::UserJourney.from_graph(graph, theme: theme)
      end

      def render_scene_title(svg, scene)
        svg << label_element(scene.title) if scene.title
      end

      def render_typed_task(svg, task)
        group = Svg::Group.new.tap { |item| item.id = "task-#{task.id}" }
        group << task_box(task.box)
        task.labels.each { |label| group << label_element(label) }
        svg << group
      end

      def task_box(box)
        Svg::Rect.new.tap do |rect|
          set_box_geometry(rect, box)
          set_box_style(rect, box)
        end
      end

      def set_box_geometry(rect, box)
        rect.x = box.x
        rect.y = box.y
        rect.width = box.width
        rect.height = box.height
      end

      def set_box_style(rect, box)
        style = box.style.to_sym
        rect.fill = theme_color(SCORE_COLOR_ROLES.fetch(style))
        rect.stroke = theme_color(:node_stroke)
        rect.stroke_width = "2"
        rect.rx = box.corner_radius
        rect.ry = box.corner_radius
      end

      def label_element(label)
        Svg::Text.new.tap do |text|
          set_label_geometry(text, label)
          set_label_style(text, label)
          set_label_class(text, label)
        end
      end

      def set_label_geometry(text, label)
        text.x = label.x
        text.y = label.y
        text.text_anchor = label.text_anchor if label.text_anchor
      end

      def set_label_style(text, label)
        text.content = label.text
        text.fill = label_color(label.style)
        text.font_family = theme_typography(:font_family)
        text.font_size = number_string(label.font_size)
        text.font_weight = label.font_weight if label.font_weight
      end

      def set_label_class(text, label)
        text.class_name = "journey-section" if label.style == "section"
      end

      def render_typed_arrow(arrow, svg)
        group = Svg::Group.new.tap { |item| item.id = "arrow-#{arrow.id}" }
        group << typed_arrow_line(arrow.line)
        group << typed_arrow_head(arrow.head_path)
        svg << group
      end

      def typed_arrow_line(source)
        Svg::Line.new.tap do |line|
          line.x1 = source.x1
          line.y1 = source.y1
          line.x2 = source.x2
          line.y2 = source.y2
          set_arrow_style(line)
        end
      end

      def typed_arrow_head(path_data)
        Svg::Path.new.tap do |path|
          path.d = path_data
          path.fill = "none"
          set_arrow_style(path)
        end
      end

      def set_arrow_style(element)
        element.stroke = theme_color(:edge_stroke)
        element.stroke_width = "2"
      end

      def label_color(style)
        if %w[section actors].include?(style)
          return theme_color(:foreground_secondary)
        end

        theme_color(:foreground)
      end

      def number_string(value)
        value.to_i == value ? value.to_i.to_s : value.to_s
      end
    end
  end
end
