# frozen_string_literal: true

require_relative "../text"
require_relative "../../../error/score_error"
require_relative "../../../diagram/user_journey"

module Sirena
  module Parser
    module Native
      module Builders
        # Builds Diagram::UserJourney from the native parse tree of the
        # +user_journey+ entry, with the Ruby builder's model.
        class UserJourney
          # @param tree [Hash, Array, Parsanol::Slice] native parse tree
          # @return [Diagram::UserJourney]
          # @raise [Parser::ScoreError] for a score outside 1..5
          def apply(tree)
            diagram = Diagram::UserJourney.new
            section = nil
            Text.items(tree).each do |item|
              section = consume(item, diagram, section)
            end
            diagram.sections << section if section
            diagram
          end

          private

          def consume(item, diagram, section)
            return add_task(item[:task], section) if item.key?(:task)
            return start_section(item, diagram, section) if item[:section]

            diagram.title = text(item[:title]) if item.key?(:title)
            section
          end

          def start_section(item, diagram, section)
            diagram.sections << section if section
            Diagram::JourneySection.new(name: text(item[:section]))
          end

          def text(node)
            Text.of(node[:text]).strip
          end

          def add_task(node, section)
            section ||= Diagram::JourneySection.new(name: "")
            section.tasks << build_task(node)
            section
          end

          def build_task(node)
            task = Diagram::JourneyTask.new
            task.name = Text.of(node[:name]).strip
            task.score = Text.of(node[:score]).to_i
            validate_score!(task.score)
            task.actors = actors(node)
            task
          end

          # An omitted actor group is none; an empty one is a single blank
          # actor; a lone actor is kept even if blank; several drop blanks.
          def actors(node)
            return [] unless node.key?(:actors)

            names = Text.of(node[:actors]).split(",", -1).map(&:strip)
            return [""] if names.empty?
            return names if names.one?

            names.reject(&:empty?)
          end

          def validate_score!(score)
            return if score.between?(1, 5)

            raise Parser::ScoreError,
                  "Score must be between 1 and 5, got #{score}"
          end
        end
      end
    end
  end
end
