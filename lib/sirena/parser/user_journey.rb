# frozen_string_literal: true

require 'parslet'
require_relative 'base'
require_relative '../diagram/user_journey'

module Sirena
  module Parser
    # Parslet grammar for User Journey diagrams
    class UserJourneyGrammar < Parslet::Parser
      rule(:sp) { match('[ \t]').repeat(1) }
      rule(:sp?) { sp.maybe }
      rule(:nl) { str("\n") }

      rule(:journey) { str('journey') >> sp? >> (nl | any.absent?) }
      rule(:title_decl) { sp? >> str('title') >> sp >> text_line.as(:title) >> (nl | any.absent?) }
      rule(:section_decl) do
        sp? >> str('section') >> sp >> text_line.as(:section) >> (nl | any.absent?)
      end

      rule(:text_line) { (nl.absent? >> str(':').absent? >> any).repeat(1) }
      rule(:task_text) { (str(':').absent? >> nl.absent? >> any).repeat(1) }
      rule(:actor_text) { (match('[,\n]').absent? >> any).repeat(1) }

      rule(:task_line) do
        sp? >>
          task_text.as(:task) >> str(':') >> sp? >>
          match('[0-9]').repeat(1).as(:score) >> str(':') >> sp? >>
          actor_list.as(:actors) >> sp? >> (nl | any.absent?)
      end

      rule(:actor_list) do
        actor_text.as(:actor) >>
          (sp? >> str(',') >> sp? >> actor_text.as(:actor)).repeat
      end

      rule(:line) { title_decl | section_decl | task_line | comment_line | blank_line }
      rule(:comment_line) { sp? >> str('%%') >> (nl.absent? >> any).repeat >> nl }
      rule(:blank_line) { sp? >> nl }

      rule(:journey_doc) do
        journey >>
          line.repeat.as(:lines)
      end

      root(:journey_doc)
    end

    # User Journey diagram parser using Parslet
    class UserJourneyParser < Base
      def parse(source)
        grammar = UserJourneyGrammar.new

        begin
          tree = grammar.parse(source)
        rescue Parslet::ParseFailed => e
          raise ParseError, "Parse error: #{e.parse_failure_cause.ascii_tree}"
        end

        build_diagram_from_tree(tree)
      end

      private

      def build_diagram_from_tree(tree)
        diagram = Diagram::UserJourney.new
        current_section = nil

        lines = Array(tree[:lines])

        lines.each do |line|
          next unless line.is_a?(Hash)

          if line[:title]
            diagram.title = line[:title].to_s.strip
          elsif line[:section]
            # Save previous section
            diagram.sections << current_section if current_section

            # Create new section
            current_section = Diagram::JourneySection.new
            current_section.name = line[:section].to_s.strip
          elsif line[:task] && current_section
            # Parse task
            task = Diagram::JourneyTask.new
            task.name = line[:task].to_s.strip
            task.score = line[:score].to_s.to_i

            validate_score!(task.score)

            # Extract actors
            actors_data = line[:actors]
            task.actors = if actors_data.is_a?(Array)
                            actors_data.map do |a|
                              a[:actor].to_s.strip
                            end.reject(&:empty?)
                          elsif actors_data.is_a?(Hash) && actors_data[:actor]
                            [actors_data[:actor].to_s.strip]
                          else
                            []
                          end

            current_section.tasks << task
          end
        end

        # Add final section
        diagram.sections << current_section if current_section

        diagram
      end

      def validate_score!(score)
        return if score >= 1 && score <= 5

        raise ParseError, "Score must be between 1 and 5, got #{score}"
      end
    end
  end
end
