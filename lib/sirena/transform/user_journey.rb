# frozen_string_literal: true

require_relative 'base'
require_relative '../diagram/user_journey'

module Sirena
  module Transform
    # User Journey diagram transformer for converting journey models to graphs.
    #
    # Converts a typed user journey model into a generic graph structure
    # suitable for layout computation by elkrb. Handles task box sizing
    # based on task name and actor count, sequential flow between tasks,
    # and horizontal timeline layout.
    #
    # @example Transform a user journey
    #   transform = UserJourneyTransform.new
    #   graph = transform.to_graph(user_journey)
    class UserJourneyTransform < Base
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

      # Converts a user journey to a graph structure.
      #
      # @param diagram [Diagram::UserJourney] the user journey to transform
      # @return [Hash] elkrb-compatible graph hash
      # @raise [TransformError] if diagram is invalid
      def to_graph(diagram)
        raise TransformError, 'Invalid diagram' unless diagram.valid?

        {
          id: diagram.id || 'user_journey',
          children: transform_tasks(diagram),
          edges: transform_task_flow(diagram),
          layoutOptions: layout_options,
          metadata: {
            title: diagram.title,
            sections: diagram.sections.map(&:name)
          }
        }
      end

      private

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
                section_index: section_idx
              }
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
              type: 'sequence'
            }
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
          font_size: DEFAULT_FONT_SIZE + 2
        )[:width]
        max_width = [max_width, name_width].max

        # Check actors width (displayed as comma-separated list)
        actors_text = task.actors.join(', ')
        actors_width = measure_text(
          actors_text,
          font_size: DEFAULT_FONT_SIZE
        )[:width]
        max_width = [max_width, actors_width].max

        # Add padding
        total_width = max_width + (TASK_PADDING * 2)

        {
          width: total_width,
          height: TASK_HEIGHT
        }
      end

      def task_labels(task)
        labels = []

        # Task name label
        name_dims = measure_text(
          task.name,
          font_size: DEFAULT_FONT_SIZE + 2
        )

        labels << {
          text: task.name,
          width: name_dims[:width],
          height: name_dims[:height],
          position: :top
        }

        # Score label
        score_text = task.score.to_s
        score_dims = measure_text(
          score_text,
          font_size: DEFAULT_FONT_SIZE + 4
        )

        labels << {
          text: score_text,
          width: score_dims[:width],
          height: score_dims[:height],
          position: :center
        }

        # Actors label
        actors_text = task.actors.join(', ')
        actors_dims = measure_text(
          actors_text,
          font_size: DEFAULT_FONT_SIZE - 2
        )

        labels << {
          text: actors_text,
          width: actors_dims[:width],
          height: actors_dims[:height],
          position: :bottom
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
          ElkOptions::NODE_PLACEMENT => 'SIMPLE',
          ElkOptions::MODEL_ORDER => 'NODES_AND_EDGES',
          ElkOptions::HIERARCHY_HANDLING => 'INCLUDE_CHILDREN'
        )
      end
    end
  end
end
