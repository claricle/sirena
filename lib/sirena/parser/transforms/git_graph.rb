# frozen_string_literal: true

require "parslet"

module Sirena
  module Parser
    module Transforms
      # Transform for Git Graph diagrams
      class GitGraph < Parslet::Transform
        # Current state tracking
        class State
          attr_accessor :current_branch, :branches, :commits, :commit_counter

          def initialize
            @current_branch = "main"
            @branches = { "main" => { order: 0, created_at: nil } }
            @commits = []
            @commit_counter = 0
          end

          def add_commit(options = {})
            @commit_counter += 1
            commit_id = options[:id] || "commit-#{@commit_counter}"

            commit = {
              id: commit_id,
              type: options[:type] || "NORMAL",
              tag: options[:tag],
              branch_name: @current_branch,
              parent_ids: find_parents,
              is_merge: options[:is_merge] || false,
              merge_branch: options[:merge_branch],
              is_cherry_pick: options[:is_cherry_pick] || false,
              cherry_pick_parent: options[:cherry_pick_parent]
            }

            @commits << commit
            commit
          end

          def add_branch(name, order = nil)
            return if @branches.key?(name)

            @branches[name] = {
              order: order,
              parent_branch: @current_branch,
              created_at: @commits.last&.fetch(:id)
            }
          end

          def checkout_branch(name)
            @current_branch = name
          end

          def merge_branch(branch_name, options = {})
            add_commit(
              options.merge(
                is_merge: true,
                merge_branch: branch_name
              )
            )
          end

          def cherry_pick(options = {})
            add_commit(
              options.merge(is_cherry_pick: true)
            )
          end

          def extract_options(options)
            return {} unless options

            opts = {}
            options_array = Array(options)

            options_array.each do |opt|
              next unless opt.is_a?(Hash)

              opts[:id] = opt[:id].to_s if opt[:id]
              opts[:type] = opt[:type].to_s if opt[:type]
              opts[:tag] = opt[:tag].to_s if opt[:tag]
              opts[:cherry_pick_parent] = opt[:parent].to_s if opt[:parent]
            end

            opts
          end

          private

          def find_parents
            # Find the last commit on the current branch
            parent = @commits.reverse.find do |c|
              c[:branch_name] == @current_branch
            end

            parent ? [parent[:id]] : []
          end
        end

        # Statement handlers
        rule(statements: subtree(:stmts)) do
          state = State.new
          stmts_array = Array(stmts)

          stmts_array.each do |stmt|
            next unless stmt.is_a?(Hash)

            if stmt.key?(:commit)
              # commit[:options] contains the parsed options if any
              commit_data = stmt[:commit]
              if commit_data.is_a?(Hash) && commit_data.key?(:options)
                options = state.extract_options(commit_data[:options])
              else
                options = {}
              end
              state.add_commit(options)
            elsif stmt.key?(:branch)
              name = stmt[:branch][:name].to_s
              options = stmt[:branch][:options]
              order = nil

              if options.is_a?(Array)
                order_opt = options.find { |o| o.is_a?(Hash) && o.key?(:order) }
                order = order_opt[:order].to_i if order_opt
              elsif options.is_a?(Hash) && options.key?(:order)
                order = options[:order].to_i
              end

              state.add_branch(name, order)
            elsif stmt.key?(:checkout)
              state.checkout_branch(stmt[:checkout][:branch].to_s)
            elsif stmt.key?(:switch)
              state.checkout_branch(stmt[:switch][:branch].to_s)
            elsif stmt.key?(:merge)
              branch = stmt[:merge][:branch].to_s
              options = state.extract_options(stmt[:merge][:options])
              state.merge_branch(branch, options)
            elsif stmt.key?(:cherry_pick)
              options = state.extract_options(stmt[:cherry_pick][:options])
              state.cherry_pick(options)
            end
          end

          # Convert state to diagram structure
          {
            commits: state.commits,
            branches: state.branches.map do |name, info|
              {
                name: name,
                order: info[:order],
                parent_branch: info[:parent_branch],
                created_at_commit: info[:created_at]
              }
            end
          }
        end
      end
    end
  end
end