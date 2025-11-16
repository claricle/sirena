# frozen_string_literal: true

require 'lutaml/model'
require_relative 'base'

module Sirena
  module Diagram
    # Represents a task in a user journey.
    #
    # A task has a name, score (1-5 indicating satisfaction), and a
    # collection of actors involved in performing the task.
    class JourneyTask < Lutaml::Model::Serializable
      # Task name/description
      attribute :name, :string

      # Task satisfaction score (1-5 range)
      attribute :score, :integer

      # Collection of actor names involved in this task
      attribute :actors, :string, collection: true, default: -> { [] }

      # Validates the task has required fields.
      #
      # @return [Boolean] true if task is valid
      def valid?
        !name.nil? && !name.empty? &&
          !score.nil? &&
          score >= 1 && score <= 5 &&
          !actors.nil? && !actors.empty?
      end

      # Returns the color for this task based on score.
      #
      # @return [String] color indicator (:red, :yellow, :green)
      def score_color
        case score
        when 1..2
          :red
        when 3
          :yellow
        when 4..5
          :green
        else
          :yellow
        end
      end
    end

    # Represents a section grouping in a user journey.
    #
    # A section groups related tasks together, representing a phase
    # or stage in the user journey.
    class JourneySection < Lutaml::Model::Serializable
      # Section name/title
      attribute :name, :string

      # Collection of tasks in this section
      attribute :tasks, JourneyTask, collection: true,
                                     default: -> { [] }

      # Validates the section has required fields.
      #
      # @return [Boolean] true if section is valid
      def valid?
        !name.nil? && !name.empty? && tasks.all?(&:valid?)
      end
    end

    # User Journey diagram model.
    #
    # Represents a complete user journey diagram showing the tasks users
    # perform, grouped into sections, with satisfaction scores and actor
    # involvement.
    #
    # @example Creating a simple user journey
    #   diagram = UserJourney.new
    #   diagram.title = "Customer Shopping Journey"
    #   section = JourneySection.new.tap do |s|
    #     s.name = "Shopping"
    #   end
    #   task = JourneyTask.new.tap do |t|
    #     t.name = "Browse products"
    #     t.score = 5
    #     t.actors = ["Customer"]
    #   end
    #   section.tasks << task
    #   diagram.sections << section
    class UserJourney < Base
      # Optional diagram title
      attribute :title, :string

      # Collection of journey sections
      attribute :sections, JourneySection, collection: true,
                                           default: -> { [] }

      # Returns the diagram type identifier.
      #
      # @return [Symbol] :user_journey
      def diagram_type
        :user_journey
      end

      # Validates the user journey structure.
      #
      # A user journey is valid if:
      # - It has at least one section
      # - All sections are valid
      # - All tasks within sections are valid
      #
      # @return [Boolean] true if user journey is valid
      def valid?
        return false if sections.nil? || sections.empty?
        return false unless sections.all?(&:valid?)

        true
      end

      # Returns all tasks across all sections.
      #
      # @return [Array<JourneyTask>] all tasks in the journey
      def all_tasks
        sections.flat_map(&:tasks)
      end

      # Returns all unique actors involved in the journey.
      #
      # @return [Array<String>] unique actor names
      def all_actors
        all_tasks.flat_map(&:actors).uniq
      end

      # Finds tasks by score.
      #
      # @param score [Integer] the score to filter by (1-5)
      # @return [Array<JourneyTask>] tasks with the given score
      def tasks_by_score(score)
        all_tasks.select { |t| t.score == score }
      end

      # Finds tasks by actor.
      #
      # @param actor [String] the actor name
      # @return [Array<JourneyTask>] tasks involving the actor
      def tasks_by_actor(actor)
        all_tasks.select { |t| t.actors.include?(actor) }
      end
    end
  end
end
