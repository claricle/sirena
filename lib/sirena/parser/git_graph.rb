# frozen_string_literal: true

require_relative "base"
require_relative "grammars/git_graph"
require_relative "transforms/git_graph"
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
    #   parser = GitGraphParser.new
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
    class GitGraphParser < Base
      # Parses git graph diagram source into a GitGraph model.
      #
      # @param source [String] the Mermaid git graph diagram source
      # @return [Diagram::GitGraph] the parsed git graph diagram
      # @raise [ParseError] if syntax is invalid
      def parse(source)
        grammar = Grammars::GitGraph.new

        begin
          parse_tree = grammar.parse(source)
        rescue Parslet::ParseFailed => e
          raise ParseError, "Syntax error at #{e.parse_failure_cause.pos}: " \
                           "#{e.parse_failure_cause}"
        end

        # Transform parse tree to diagram model
        transform = Transforms::GitGraph.new
        result = transform.apply(parse_tree)

        # Create the diagram model
        create_diagram(result)
      end

      private

      def create_diagram(result)
        diagram = Diagram::GitGraph.new

        # Add commits
        result[:commits].each do |commit_data|
          commit = Diagram::GitGraph::Commit.new(
            id: commit_data[:id],
            type: commit_data[:type],
            tag: commit_data[:tag],
            branch_name: commit_data[:branch_name],
            parent_ids: commit_data[:parent_ids],
            is_merge: commit_data[:is_merge],
            merge_branch: commit_data[:merge_branch],
            is_cherry_pick: commit_data[:is_cherry_pick],
            cherry_pick_parent: commit_data[:cherry_pick_parent]
          )
          diagram.commits << commit
        end

        # Add branches
        result[:branches].each do |branch_data|
          branch = Diagram::GitGraph::Branch.new(
            name: branch_data[:name],
            order: branch_data[:order],
            parent_branch: branch_data[:parent_branch],
            created_at_commit: branch_data[:created_at_commit]
          )
          diagram.branches << branch
        end

        diagram
      end
    end
  end
end