# frozen_string_literal: true

require_relative "base"
require_relative "user_journey_geometry"
require_relative "../diagram/user_journey"
require_relative "../notation/mermaid/ir_adapters/user_journey"

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
      include UserJourneyGeometry

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

      JOURNEY_ELK_OPTIONS = {
        ElkOptions::NODE_NODE_SPACING => TASK_SPACING,
        ElkOptions::LAYER_SPACING => TASK_SPACING,
        ElkOptions::EDGE_NODE_SPACING => 30,
        ElkOptions::EDGE_EDGE_SPACING => 20,
        ElkOptions::NODE_PLACEMENT => "SIMPLE",
        ElkOptions::MODEL_ORDER => "NODES_AND_EDGES",
        ElkOptions::HIERARCHY_HANDLING => "INCLUDE_CHILDREN",
      }.freeze
      private_constant :JOURNEY_ELK_OPTIONS

      class Box < Lutaml::Model::Serializable
        attribute :x, :float
        attribute :y, :float
        attribute :width, :float
        attribute :height, :float
        attribute :corner_radius, :float
        attribute :fill, :string
      end

      class Label < Lutaml::Model::Serializable
        attribute :text, :string
        attribute :x, :float
        attribute :y, :float
        attribute :font_size, :float
        attribute :text_anchor, :string
        attribute :font_weight, :string
        attribute :style, :string
        attribute :fill, :string
      end

      # A coloured circle: a legend marker or an actor on a task.
      class Dot < Lutaml::Model::Serializable
        attribute :x, :float
        attribute :y, :float
        attribute :colour, :string
        attribute :name, :string
        attribute :index, :integer
      end

      class Actor < Lutaml::Model::Serializable
        attribute :dot, Dot
        attribute :labels, Label, collection: true, default: -> { [] }
      end

      class Section < Lutaml::Model::Serializable
        attribute :box, Box
        attribute :labels, Label, collection: true, default: -> { [] }
        attribute :number, :integer
      end

      class Task < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :box, Box
        attribute :labels, Label, collection: true, default: -> { [] }
        attribute :dots, Dot, collection: true, default: -> { [] }
        attribute :number, :integer
        attribute :score, :float
        attribute :line_end, :float
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
        attribute :line, Line
        attribute :head_path, :string
      end

      class Scene < Layout::Scene
        attribute :id, :string
        attribute :view_box, :string
        attribute :title, Label
        attribute :acc_title, :string
        attribute :acc_description, :string
        attribute :legend, Actor, collection: true, default: -> { [] }
        attribute :sections, Section, collection: true, default: -> { [] }
        attribute :tasks, Task, collection: true, default: -> { [] }
        attribute :arrows, Arrow, collection: true, default: -> { [] }
      end

      def self.from_graph(graph, theme: nil)
        layout = new
        layout.theme = theme if theme
        return layout.to_graph(graph) if graph.is_a?(IR::Graph)

        layout.send(:scene_from_graph, graph)
      end

      # Converts a user journey to a graph structure.
      #
      # @param diagram [Diagram::UserJourney, IR::Graph] source journey graph
      # @return [Hash] elkrb-compatible graph hash
      def build_graph(diagram)
        graph = ir_graph(diagram)
        sections = section_nodes(graph)
        {
          id: graph.id,
          children: transform_tasks(graph, sections),
          edges: transform_task_flow(graph),
          layoutOptions: layout_options,
          metadata: journey_metadata(graph, sections),
        }
      end

      private

      def journey_metadata(graph, sections)
        {
          title: graph.label,
          sections: sections.map(&:label),
          acc_title: graph.accessibility_title,
          acc_description: graph.accessibility_description,
        }
      end

      def scene(diagram)
        scene_from_graph(build_graph(diagram))
      end

      def ir_graph(diagram)
        return diagram if diagram.is_a?(IR::Graph)

        Notation::Mermaid::IRAdapters::UserJourney.call(diagram)
      end

      def section_nodes(graph)
        graph.nodes.select { |node| node.role == "journey_section" }
      end

      def transform_tasks(graph, sections)
        section_indexes = sections.each_with_index.to_h do |section, index|
          [section.id, index]
        end
        graph.nodes.filter_map do |node|
          next unless task_node?(node)

          transformed_task(graph, node, sections, section_indexes)
        end
      end

      def transformed_task(graph, node, sections, section_indexes)
        metadata = task_metadata(graph, node, sections, section_indexes)
        dimensions = calculate_task_dimensions(metadata)
        {
          id: node.id, width: dimensions[:width], height: dimensions[:height],
          labels: task_labels(metadata), metadata: metadata
        }
      end

      def task_node?(node)
        node.role&.start_with?("journey_task_")
      end

      def task_metadata(graph, node, sections, section_indexes)
        section = sections.find { |candidate| candidate.id == node.parent_id }
        {
          name: node.label,
          score: normalized_score(node.properties.weight),
          score_color: node.role.delete_prefix("journey_task_"),
          actors: actor_names(graph, node.id),
          section_name: section&.label,
          section_index: section_indexes[node.parent_id],
        }
      end

      def normalized_score(score)
        return score.to_i if score&.finite? && score == score.to_i

        score
      end

      def actor_names(graph, task_id)
        graph.nodes.filter_map do |node|
          actor = node.role == "journey_actor" && node.parent_id == task_id
          node.label if actor
        end
      end

      def transform_task_flow(graph)
        graph.edges.filter_map do |edge|
          next unless edge.role == "sequence"

          {
            id: edge.id, sources: [edge.source_id], targets: [edge.target_id],
            metadata: { type: "sequence" }
          }
        end
      end

      def calculate_task_dimensions(task)
        widths = [
          MIN_TASK_WIDTH,
          measured_width(task[:name], DEFAULT_FONT_SIZE + 2),
          measured_width(task[:actors].join(", "), DEFAULT_FONT_SIZE),
        ]
        {
          width: widths.max + (TASK_PADDING * 2),
          height: TASK_HEIGHT,
        }
      end

      def measured_width(text, font_size)
        measure_text(text, font_size: font_size)[:width]
      end

      def task_labels(task)
        [
          task_label(task[:name], DEFAULT_FONT_SIZE + 2, :top),
          task_label(task[:score].to_s, DEFAULT_FONT_SIZE + 4, :center),
          task_label(task[:actors].join(", "), DEFAULT_FONT_SIZE - 2, :bottom),
        ]
      end

      def task_label(text, font_size, position)
        dimensions = measure_text(text, font_size: font_size)
        {
          text: text, width: dimensions[:width], height: dimensions[:height],
          position: position
        }
      end

      def layout_options
        # User journeys use layered algorithm for sequential task flow
        # DIRECTION_RIGHT provides left-to-right horizontal timeline
        # SIMPLE node placement maintains task order in journey sequence
        build_elk_options(
          algorithm: ALGORITHM_LAYERED, direction: DIRECTION_RIGHT,
          **JOURNEY_ELK_OPTIONS
        )
      end
    end
  end
end
