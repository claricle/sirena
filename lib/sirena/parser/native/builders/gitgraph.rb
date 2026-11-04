# frozen_string_literal: true

require_relative "../text"
require_relative "../../builders/git_graph"

module Sirena
  module Parser
    module Native
      module Builders
        # Builds the git graph model data from the native parse tree of
        # the +gitgraph+ entry. The tree's statements have the shape the
        # Parslet transform consumes, so the same replay State turns them
        # into commits and branches, with the same errors.
        class GitGraph
          DEFAULT_ORIENTATION = "LR"
          private_constant :DEFAULT_ORIENTATION

          # @param tree [Hash, Parsanol::Slice] native parse tree
          # @param main_branch_name [String] name of the first branch
          # @return [Array(Hash, String)] the replayed graph data and the
          #   orientation
          # @raise [Parser::ParseError] for an unknown branch, a repeated
          #   merge id and the other replay errors
          def apply(tree, main_branch_name: "main")
            hash = tree.is_a?(Hash) ? tree : {}
            statements = Text.items(hash[:statements])
            state = Parser::Builders::GitGraph::State.new(main_branch_name)
            [state.process(statements).to_h,
             hash.fetch(:direction, DEFAULT_ORIENTATION).to_s]
          end
        end
      end
    end
  end
end
