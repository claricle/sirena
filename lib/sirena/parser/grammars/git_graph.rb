# frozen_string_literal: true

require_relative "common"

module Sirena
  module Parser
    module Grammars
      # Parslet grammar for Git Graph diagrams
      class GitGraph < Common

        rule(:diagram) do
          ws? >>
            header >>
            ws? >>
            statements.maybe.as(:statements) >>
            ws?
        end

        rule(:header) do
          str("gitGraph") >>
            (str(" TB:") | str(" LR:") | str("TB:") | str("LR:") | str(":")).maybe >>
            ws?
        end

        rule(:statements) do
          (statement >> ws?).repeat(1)
        end

        rule(:statement) do
          commit_stmt |
          branch_stmt |
          checkout_stmt |
          switch_stmt |
          merge_stmt |
          cherry_pick_stmt
        end

        rule(:commit_stmt) do
          (
            str("commit") >>
            commit_options.maybe.as(:options)
          ).as(:commit) >>
            line_end
        end

        rule(:commit_options) do
          space >> (commit_option >> space?).repeat(1)
        end

        rule(:commit_option) do
          commit_id | commit_type | commit_tag
        end

        rule(:commit_id) do
          str("id:") >> space? >>
            (str('"') >> match('[^"]').repeat(1).as(:id) >> str('"') |
             str("'") >> match("[^']").repeat(1).as(:id) >> str("'") |
             match('[^\s,]').repeat(1).as(:id))
        end

        rule(:commit_type) do
          str("type:") >> space? >>
            (str("NORMAL") | str("REVERSE") | str("HIGHLIGHT")).as(:type)
        end

        rule(:commit_tag) do
          str("tag:") >> space? >>
            (str('"') >> match('[^"]').repeat(1).as(:tag) >> str('"') |
             str("'") >> match("[^']").repeat(1).as(:tag) >> str("'") |
             match('[^\s,]').repeat(1).as(:tag))
        end

        rule(:branch_stmt) do
          (
            str("branch") >> space >>
            branch_name.as(:name) >>
            branch_options.maybe.as(:options)
          ).as(:branch) >>
            line_end
        end

        rule(:branch_name) do
          match('[a-zA-Z0-9_-]').repeat(1)
        end

        rule(:branch_options) do
          space >> (branch_option >> space?).repeat(1)
        end

        rule(:branch_option) do
          str("order:") >> space? >> match('[0-9]').repeat(1).as(:order)
        end

        rule(:checkout_stmt) do
          (
            str("checkout") >> space >>
            branch_name.as(:branch)
          ).as(:checkout) >>
            line_end
        end

        rule(:switch_stmt) do
          (
            str("switch") >> space >>
            branch_name.as(:branch)
          ).as(:switch) >>
            line_end
        end

        rule(:merge_stmt) do
          str("merge") >> space >>
            (
              branch_name.as(:branch) >>
              merge_options.maybe.as(:options)
            ).as(:merge) >>
            line_end
        end

        rule(:merge_options) do
          space >> (merge_option >> space?).repeat(1)
        end

        rule(:merge_option) do
          commit_id | commit_type | commit_tag |
          (str("random:") >> quoted_string)
        end

        rule(:cherry_pick_stmt) do
          (
            str("cherry-pick") >> space >>
            cherry_pick_options.as(:options)
          ).as(:cherry_pick) >>
            line_end
        end

        rule(:cherry_pick_options) do
          (cherry_pick_option >> space?).repeat(1)
        end

        rule(:cherry_pick_option) do
          cherry_pick_id | cherry_pick_parent | commit_tag
        end

        rule(:cherry_pick_id) do
          str("id:") >> space? >>
            (str('"') >> match('[^"]').repeat(1).as(:id) >> str('"') |
             str("'") >> match("[^']").repeat(1).as(:id) >> str("'") |
             match('[^\s,]').repeat(1).as(:id))
        end

        rule(:cherry_pick_parent) do
          str("parent:") >> space? >>
            (str('"') >> match('[^"]').repeat(1).as(:parent) >> str('"') |
             str("'") >> match("[^']").repeat(1).as(:parent) >> str("'") |
             match('[^\s,]').repeat(1).as(:parent))
        end

        rule(:quoted_string) do
          str('"') >> match('[^"]').repeat(0) >> str('"') |
          str("'") >> match("[^']").repeat(0) >> str("'")
        end

        root(:diagram)
      end
    end
  end
end