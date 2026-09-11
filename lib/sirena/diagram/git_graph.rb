# frozen_string_literal: true

require "lutaml/model"
require_relative "base"

module Sirena
  module Diagram
    # Represents a Git Graph diagram
    class GitGraph < Base
      # Represents a commit in the git graph
      class Commit < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :message, :string
        attribute :type, :string, default: -> { "NORMAL" }
        attribute :tag, :string
        attribute :branch_name, :string
        attribute :parent_ids, :string, collection: true, default: -> { [] }
        attribute :is_merge, :boolean, default: -> { false }
        attribute :merge_branch, :string
        attribute :is_cherry_pick, :boolean, default: -> { false }
        attribute :cherry_pick_parent, :string
      end

      # Represents a branch in the git graph
      class Branch < Lutaml::Model::Serializable
        attribute :name, :string
        attribute :order, :integer
        attribute :parent_branch, :string
        attribute :created_at_commit, :string
      end

      attribute :orientation, :string, default: -> { "LR" }
      attribute :commits, Commit, collection: true, default: -> { [] }
      attribute :branches, Branch, collection: true, default: -> { [] }

      # Returns the diagram type identifier.
      #
      # @return [Symbol] :git_graph
      def diagram_type
        :git_graph
      end

      # Git graphs have no validation rules yet. See TODO.foundation's
      # corpus burndown for real validation; this is deliberately trivial.
      #
      # @return [Boolean] true
      def valid?
        true
      end
    end
  end
end