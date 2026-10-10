# frozen_string_literal: true

require_relative "base"
require_relative "grammars/git_graph"
require_relative "builders/git_graph"
require_relative "../diagram/git_graph"

module Sirena
  module Parser
    # Git Graph parser for Mermaid gitGraph diagram syntax.
    #
    # Uses Parslet grammar-based parsing to handle git graph syntax
    # with commits, branches, merges, and cherry-picks.
    #
    # Parses git graphs with support for:
    # - Commit declarations with id, type, and tag
    # - Branch creation with optional order
    # - Checkout/switch operations
    # - Merge operations
    # - Cherry-pick operations
    # - Commit types (NORMAL, REVERSE, HIGHLIGHT)
    #
    # @example Parse a simple git graph
    #   parser = GitGraph.new
    #   source = <<~MERMAID
    #     gitGraph
    #       commit id: "Initial"
    #       branch develop
    #       checkout develop
    #       commit id: "Feature"
    #       checkout main
    #       merge develop
    #   MERMAID
    #   diagram = parser.parse(source)
    class GitGraph < Base
      COMMIT_ATTRIBUTES = %i[
        id message type tag branch_name parent_ids is_merge merge_branch
        is_cherry_pick cherry_pick_parent
      ].freeze
      BRANCH_ATTRIBUTES = %i[
        name order parent_branch created_at_commit
      ].freeze

      # Parses git graph diagram source into a GitGraph model.
      #
      # @param source [String] the Mermaid git graph diagram source
      # @return [Diagram::GitGraph] the parsed git graph diagram
      # @raise [ParseError] if syntax is invalid
      def parse(source)
        tree = parse_with_grammar(Grammars::GitGraph.new, source)
        result = Builders::GitGraph.new.apply(tree.slice(:statements))
        create_diagram(result, tree.fetch(:direction, "LR").to_s)
      end

      private

      def create_diagram(result, orientation)
        diagram = Diagram::GitGraph.new(
          orientation: orientation,
          acc_title: result[:acc_title],
          acc_description: result[:acc_description],
        )
        append_commits(diagram, result[:commits])
        append_branches(diagram, result[:branches])
        diagram
      end

      def append_commits(diagram, commits)
        commits.each { |data| diagram.commits << build_commit(data) }
      end

      def build_commit(data)
        Diagram::GitGraph::Commit.new(**data.slice(*COMMIT_ATTRIBUTES))
      end

      def append_branches(diagram, branches)
        branches.each { |data| diagram.branches << build_branch(data) }
      end

      def build_branch(data)
        Diagram::GitGraph::Branch.new(**data.slice(*BRANCH_ATTRIBUTES))
      end
    end
  end
end
