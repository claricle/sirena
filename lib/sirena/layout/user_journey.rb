# frozen_string_literal: true

require_relative "base"
require_relative "grid"
require_relative "../diagram/user_journey"

module Sirena
  module Layout
    # User Journey diagram transformer for converting journey models to graphs.
    #
    # Converts a typed user journey model into a generic graph structure
    # suitable for layout computation by elkrb. Handles task box sizing
    # based on task name and actor count, sequential flow between tasks,
    # and horizontal timeline layout.
    #
    # @example Transform a user journey
    #   transform = UserJourney.new
    #   graph = transform.to_graph(user_journey)
    class UserJourney < Base
      # Default font size for text measurement
      DEFAULT_FONT_SIZE = 14

      # Minimum width for a task box
      MIN_TASK_WIDTH = 120

      # Height per task box
      TASK_HEIGHT = 80

      # Padding within task box
      TASK_PADDING = 10

      # Horizontal spacing between tasks
      TASK_SPACING = 60

      # Vertical spacing between sections
      SECTION_SPACING = 40

      TITLE_FONT_SIZE = 20
      SECTION_FONT_SIZE = 16
      TASK_NAME_FONT_SIZE = 14
      SCORE_FONT_SIZE = 18
      ACTOR_FONT_SIZE = 11
      TITLE_PADDING = 20
      SECTION_PADDING = 10

      class Box < Lutaml::Model::Serializable
        attribute :x, :float
        attribute :y, :float
        attribute :width, :float
        attribute :height, :float
        attribute :corner_radius, :float
        attribute :style, :string
      end

      class Label < Lutaml::Model::Serializable
        attribute :text, :string
        attribute :x, :float
        attribute :y, :float
        attribute :font_size, :float
        attribute :text_anchor, :string
        attribute :font_weight, :string
        attribute :style, :string
      end

      class Task < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :box, Box
        attribute :labels, Label, collection: true, default: -> { [] }
        attribute :section_name, :string
        attribute :section_index, :integer
      end

      class Line < Lutaml::Model::Serializable
        attribute :x1, :float
        attribute :y1, :float
        attribute :x2, :float
        attribute :y2, :float
      end

      class Arrow < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :source, :string
        attribute :target, :string
        attribute :line, Line
        attribute :head_path, :string
      end

      class Scene < Layout::Scene
        attribute :id, :string
        attribute :view_box, :string
        attribute :title, Label
        attribute :sections, Label, collection: true, default: -> { [] }
        attribute :tasks, Task, collection: true, default: -> { [] }
        attribute :arrows, Arrow, collection: true, default: -> { [] }
      end

      def self.from_graph(graph, theme: nil)
        layout = new
        layout.theme = theme if theme
        layout.send(:scene_from_graph, graph)
      end

      # Converts a user journey to a graph structure.
      #
      # @param diagram [Diagram::UserJourney] the user journey to transform
      # @return [Hash] elkrb-compatible graph hash
      def build_graph(diagram)
        {
          id: diagram.id || "user_journey",
          children: transform_tasks(diagram),
          edges: transform_task_flow(diagram),
          layoutOptions: layout_options,
          metadata: {
            title: diagram.title,
            sections: diagram.sections.map(&:name),
          },
        }
      end

      private

      def scene(diagram)
        graph = build_graph(diagram)
        Grid.apply(graph)
        scene_from_graph(graph)
      end

      def scene_from_graph(graph)
        width = document_width(graph)
        height = document_height(graph)
        Scene.new(
          id: graph[:id] || "user_journey", width: width, height: height,
          view_box: "0 0 #{width} #{height}", title: title_label(graph),
          sections: section_labels(graph), tasks: typed_tasks(graph),
          arrows: typed_arrows(graph)
        )
      end

      def document_width(graph)
        return 840 unless graph[:children]

        extent = graph[:children].map do |node|
          (node[:x] || 0) + (node[:width] || MIN_TASK_WIDTH)
        end.max || 800
        extent + 80
      end

      def document_height(graph)
        children = graph[:children]
        return 640 unless children

        extent = children.map { |node| task_bottom(node) }.max || 600
        extent + journey_title_height(graph) + 100
      end

      def task_bottom(node)
        task_y(node) + task_height(node)
      end

      def journey_title_height(graph)
        return 0 unless graph.dig(:metadata, :title)

        TITLE_FONT_SIZE + (TITLE_PADDING * 2)
      end

      def title_label(graph)
        title = graph.dig(:metadata, :title)
        return if title.nil? || title.empty?

        Label.new(
          text: title, x: 20, y: TITLE_PADDING + TITLE_FONT_SIZE,
          font_size: TITLE_FONT_SIZE, font_weight: "bold", style: "title"
        )
      end

      def section_labels(graph)
        current_y = section_start_y(graph)
        section_names(graph).map do |section_name|
          label = section_label(section_name, current_y)
          current_y += SECTION_FONT_SIZE + SECTION_PADDING + 20
          label
        end
      end

      def section_names(graph)
        graph.dig(:metadata, :sections) || grouped_tasks(graph).keys
      end

      def section_start_y(graph)
        return TITLE_PADDING unless title_label(graph)

        TITLE_PADDING + TITLE_FONT_SIZE + TITLE_PADDING
      end

      def section_label(section_name, current_y)
        Label.new(
          text: section_name, x: 20, y: current_y + SECTION_FONT_SIZE,
          font_size: SECTION_FONT_SIZE, font_weight: "bold", style: "section"
        )
      end

      def grouped_tasks(graph)
        (graph[:children] || []).group_by do |node|
          node.dig(:metadata, :section_name) || "Default"
        end
      end

      def typed_tasks(graph)
        (graph[:children] || []).map { |node| typed_task(node) }
      end

      def typed_task(node)
        metadata = node[:metadata] || {}
        Task.new(
          id: node[:id],
          box: task_box(node, metadata),
          labels: task_content(metadata, node),
          section_name: metadata[:section_name],
          section_index: metadata[:section_index],
        )
      end

      def task_box(node, metadata)
        Box.new(
          x: task_x(node), y: task_y(node),
          width: task_width(node), height: task_height(node),
          corner_radius: 5, style: task_style(metadata)
        )
      end

      def task_style(metadata)
        (metadata[:score_color] || :yellow).to_s
      end

      def task_content(metadata, node)
        center_x = task_x(node) + (task_width(node) / 2.0)
        [
          task_name_label(metadata, node, center_x),
          task_score_label(metadata, node, center_x),
          task_actor_label(metadata, node, center_x),
        ]
      end

      def task_name_label(metadata, node, center_x)
        y_position = task_y(node) + TASK_PADDING + TASK_NAME_FONT_SIZE
        task_label(metadata[:name] || "Task", [center_x, y_position],
                   TASK_NAME_FONT_SIZE, "name", "bold")
      end

      def task_score_label(metadata, node, center_x)
        y_position = task_y(node) + TASK_PADDING + TASK_NAME_FONT_SIZE + 10 +
          SCORE_FONT_SIZE
        task_label((metadata[:score] || 3).to_s, [center_x, y_position],
                   SCORE_FONT_SIZE, "score", "bold")
      end

      def task_actor_label(metadata, node, center_x)
        y_position = task_y(node) + TASK_PADDING + TASK_NAME_FONT_SIZE + 10 +
          SCORE_FONT_SIZE + 10 + ACTOR_FONT_SIZE
        task_label(Array(metadata[:actors]).join(", "), [center_x, y_position],
                   ACTOR_FONT_SIZE, "actors")
      end

      def task_label(text, position, size, style, weight = nil)
        Label.new(
          text: text, x: position[0], y: position[1], font_size: size,
          text_anchor: "middle", font_weight: weight, style: style
        )
      end

      def typed_arrows(graph)
        (graph[:edges] || []).filter_map do |edge|
          typed_arrow(edge, graph[:children] || [])
        end
      end

      def typed_arrow(edge, nodes)
        source_id = Array(edge[:sources]).first
        target_id = Array(edge[:targets]).first
        source = find_node(nodes, source_id)
        target = find_node(nodes, target_id)
        return unless source && target

        build_typed_arrow(edge[:id], source_id, target_id, source, target)
      end

      def build_typed_arrow(id, source_id, target_id, source, target)
        from_x, from_y = task_right_center(source)
        to_x, to_y = task_left_center(target)
        Arrow.new(
          id: id, source: source_id, target: target_id,
          line: Line.new(x1: from_x, y1: from_y, x2: to_x, y2: to_y),
          head_path: arrowhead_path(to_x, to_y, from_x, from_y)
        )
      end

      def task_right_center(node)
        [task_x(node) + task_width(node), task_center_y(node)]
      end

      def task_left_center(node)
        [task_x(node), task_center_y(node)]
      end

      def task_center_y(node)
        task_y(node) + (task_height(node) / 2.0)
      end

      def task_x(node)
        node[:x] || 0
      end

      def task_y(node)
        node[:y] || 0
      end

      def task_width(node)
        node[:width] || MIN_TASK_WIDTH
      end

      def task_height(node)
        node[:height] || TASK_HEIGHT
      end

      def find_node(nodes, node_id)
        nodes.find { |node| node[:id] == node_id } if node_id
      end

      def arrowhead_path(to_x, to_y, from_x, from_y)
        angle = Math.atan2(to_y - from_y, to_x - from_x)
        point1 = arrowhead_point(to_x, to_y, angle - (Math::PI / 6))
        point2 = arrowhead_point(to_x, to_y, angle + (Math::PI / 6))
        "M #{to_x},#{to_y} L #{point1.join(',')} " \
          "M #{to_x},#{to_y} L #{point2.join(',')}"
      end

      def arrowhead_point(x_position, y_position, angle)
        [x_position - (10 * Math.cos(angle)),
         y_position - (10 * Math.sin(angle))]
      end

      def transform_tasks(diagram)
        task_id = 0
        nodes = []

        diagram.sections.each_with_index do |section, section_idx|
          section.tasks.each do |task|
            dims = calculate_task_dimensions(task)

            nodes << {
              id: "task_#{task_id}",
              width: dims[:width],
              height: dims[:height],
              labels: task_labels(task),
              metadata: {
                name: task.name,
                score: task.score,
                score_color: task.score_color,
                actors: task.actors,
                section_name: section.name,
                section_index: section_idx,
              },
            }

            task_id += 1
          end
        end

        nodes
      end

      def transform_task_flow(diagram)
        # Create sequential edges between tasks
        edges = []
        all_tasks = diagram.all_tasks
        task_id = 0

        all_tasks.each_with_index do |_task, idx|
          next if idx >= all_tasks.length - 1

          edges << {
            id: "flow_#{task_id}",
            sources: ["task_#{task_id}"],
            targets: ["task_#{task_id + 1}"],
            metadata: {
              type: "sequence",
            },
          }

          task_id += 1
        end

        edges
      end

      def calculate_task_dimensions(task)
        # Calculate width based on task name and actors
        max_width = MIN_TASK_WIDTH

        # Check task name width
        name_width = measure_text(
          task.name,
          font_size: DEFAULT_FONT_SIZE + 2,
        )[:width]
        max_width = [max_width, name_width].max

        # Check actors width (displayed as comma-separated list)
        actors_text = task.actors.join(", ")
        actors_width = measure_text(
          actors_text,
          font_size: DEFAULT_FONT_SIZE,
        )[:width]
        max_width = [max_width, actors_width].max

        # Add padding
        total_width = max_width + (TASK_PADDING * 2)

        {
          width: total_width,
          height: TASK_HEIGHT,
        }
      end

      def task_labels(task)
        labels = []

        # Task name label
        name_dims = measure_text(
          task.name,
          font_size: DEFAULT_FONT_SIZE + 2,
        )

        labels << {
          text: task.name,
          width: name_dims[:width],
          height: name_dims[:height],
          position: :top,
        }

        # Score label
        score_text = task.score.to_s
        score_dims = measure_text(
          score_text,
          font_size: DEFAULT_FONT_SIZE + 4,
        )

        labels << {
          text: score_text,
          width: score_dims[:width],
          height: score_dims[:height],
          position: :center,
        }

        # Actors label
        actors_text = task.actors.join(", ")
        actors_dims = measure_text(
          actors_text,
          font_size: DEFAULT_FONT_SIZE - 2,
        )

        labels << {
          text: actors_text,
          width: actors_dims[:width],
          height: actors_dims[:height],
          position: :bottom,
        }

        labels
      end

      def layout_options
        # User journeys use layered algorithm for sequential task flow
        # DIRECTION_RIGHT provides left-to-right horizontal timeline
        # SIMPLE node placement maintains task order in journey sequence
        build_elk_options(
          algorithm: ALGORITHM_LAYERED,
          direction: DIRECTION_RIGHT,
          ElkOptions::NODE_NODE_SPACING => TASK_SPACING,
          ElkOptions::LAYER_SPACING => TASK_SPACING,
          ElkOptions::EDGE_NODE_SPACING => 30,
          ElkOptions::EDGE_EDGE_SPACING => 20,
          # SIMPLE node placement for chronological task ordering
          ElkOptions::NODE_PLACEMENT => "SIMPLE",
          ElkOptions::MODEL_ORDER => "NODES_AND_EDGES",
          ElkOptions::HIERARCHY_HANDLING => "INCLUDE_CHILDREN",
        )
      end
    end
  end
end
