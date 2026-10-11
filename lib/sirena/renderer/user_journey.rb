# frozen_string_literal: true

require_relative "base"
require_relative "../layout/user_journey"

module Sirena
  module Renderer
    # User Journey diagram renderer for converting graphs to SVG.
    #
    # Draws what mmdc draws: an actor legend on the left, a coloured band per
    # section, and for every task a box, a dashed line down to a face whose
    # height follows the score, and a dot per actor.
    #
    # @example Render a user journey
    #   renderer = UserJourney.new
    #   svg = renderer.render(laid_out_graph)
    class UserJourney < Base
      TEXT_FONT = '"Open Sans", sans-serif'
      GREY = "#666"

      # Renders a laid-out graph to SVG.
      #
      # @param graph [Hash] laid-out graph with node positions
      # @return [Svg::Document] the rendered SVG document
      def render(graph)
        scene = typed_scene(graph)
        svg = create_document(scene)
        svg.view_box = scene.view_box
        draw_body(svg, scene)
        draw_trim(svg, scene)
        svg
      end

      protected

      def typed_scene(graph)
        return graph if graph.is_a?(Layout::UserJourney::Scene)

        Layout::UserJourney.from_graph(graph, theme: theme)
      end

      def draw_body(svg, scene)
        scene.legend.each { |actor| render_actor(svg, actor) }
        scene.sections.each { |section| render_section(svg, section) }
        scene.tasks.each { |task| render_task(svg, task) }
      end

      def draw_trim(svg, scene)
        svg << title_text(scene.title) if scene.title
        scene.arrows.each { |arrow| render_timeline(svg, arrow) }
      end

      def render_actor(svg, actor)
        svg << dot_circle(actor.dot)
        actor.labels.each { |label| svg << legend_text(label) }
      end

      def legend_text(label)
        themed_text(label, fill: theme_color(:foreground))
      end

      def title_text(label)
        themed_text(label, fill: theme_color(:foreground),
                           font_weight: label.font_weight)
      end

      def themed_text(label, **extra)
        Svg::Text.new(
          x: label.x, y: label.y, content: label.text,
          font_family: theme_typography(:font_family),
          font_size: number_string(label.font_size), **extra
        )
      end

      def dot_circle(dot)
        Svg::Circle.new(
          cx: dot.x, cy: dot.y, r: dot.radius,
          class_name: "actor-#{dot.index}",
          fill: dot.colour, stroke: theme_color(:node_stroke)
        )
      end

      def render_section(svg, section)
        class_name = "journey-section section-type-#{section.number}"
        group = Svg::Group.new
        group << band_rect(section.box, class_name)
        section.labels.each { |label| group << box_text(label, class_name) }
        svg << group
      end

      def band_rect(box, class_name)
        Svg::Rect.new(
          x: box.x, y: box.y, width: box.width, height: box.height,
          rx: box.corner_radius, ry: box.corner_radius,
          class_name: class_name, fill: box.fill,
          stroke: secondary_paint
        )
      end

      def box_text(label, class_name)
        Svg::Text.new(
          x: label.x, y: label.y, content: label.text,
          class_name: class_name, fill: label.fill,
          text_anchor: label.text_anchor,
          font_family: TEXT_FONT, font_size: number_string(label.font_size)
        )
      end

      def render_task(svg, task)
        group = Svg::Group.new(id: "task-#{task.id}")
        group << task_line(task)
        render_face(group, task)
        render_task_box(group, task)
        svg << group
      end

      def render_task_box(group, task)
        group << band_rect(task.box, "task task-type-#{task.number}")
        task.dots.each { |dot| group << dot_circle(dot) }
        task.labels.each { |label| group << box_text(label, "task") }
      end

      def task_line(task)
        center_x = task.face.center_x
        Svg::Line.new(
          x1: center_x, x2: center_x, y1: task.box.y, y2: task.line_end,
          class_name: "task-line",
          stroke: secondary_paint,
          stroke_width: "1px",
          stroke_dasharray: "4 2"
        )
      end

      def render_face(group, task)
        face = task.face
        group << face_circle(face)
        group << face_features(face)
      end

      def face_circle(face)
        Svg::Circle.new(
          cx: face.center_x, cy: face.center_y, r: face.radius,
          class_name: "face", fill: "#FFF8DC",
          stroke: theme_color(:node_stroke),
          stroke_width: "2"
        )
      end

      def face_features(face)
        Svg::Group.new.tap do |group|
          face.eyes.each { |point| group << eye(point) }
          group << mouth(face.mouth)
        end
      end

      def eye(point)
        Svg::Circle.new(
          cx: point.x, cy: point.y, r: point.radius,
          fill: theme_color(:foreground),
          stroke: secondary_paint,
          stroke_width: "2"
        )
      end

      def mouth(mouth)
        return flat_mouth(mouth.line) unless mouth.path

        Svg::Path.new(
          d: mouth.path, class_name: "mouth",
          fill: theme_color(:foreground),
          stroke: secondary_paint
        )
      end

      def flat_mouth(line)
        Svg::Line.new(
          x1: line.x1, x2: line.x2, y1: line.y1, y2: line.y2,
          class_name: "mouth", stroke: secondary_paint,
          stroke_width: "1px"
        )
      end

      def render_timeline(svg, arrow)
        svg << timeline_line(arrow.line)
        svg << timeline_head(arrow.head_path)
      end

      def timeline_line(source)
        Svg::Line.new(
          x1: source.x1, y1: source.y1, x2: source.x2, y2: source.y2,
          stroke: theme_color(:edge_stroke), stroke_width: "4"
        )
      end

      def number_string(value)
        value.to_i == value ? value.to_i.to_s : value.to_s
      end

      def secondary_paint
        color = theme_color(:foreground_secondary)
        color == "#666666" ? GREY : color
      end

      def timeline_head(path_data)
        Svg::Path.new(d: path_data, fill: theme_color(:edge_stroke))
      end
    end
  end
end
