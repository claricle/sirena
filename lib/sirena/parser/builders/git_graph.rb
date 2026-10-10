# frozen_string_literal: true

require "parslet"

module Sirena
  module Parser
    module Builders
      # Transform for Git Graph diagrams
      class GitGraph < Parslet::Transform
        # Current state tracking
        class State
          attr_accessor :current_branch, :branches, :commits, :commit_counter,
                        :acc_title, :acc_description

          # An empty capture comes back from Parslet as an Array, not "".
          def self.captured_text(captured)
            captured.is_a?(Array) ? "" : captured.to_s
          end

          ESCAPES = {
            "b" => "\b", "f" => "\f", "n" => "\n", "r" => "\r",
            "t" => "\t", "v" => "\v", "0" => "\0"
          }.freeze
          private_constant :ESCAPES

          OPTION_KEYS = {
            id: :id, type: :type, tag: :tag,
            parent: :cherry_pick_parent
          }.freeze
          private_constant :OPTION_KEYS

          STATEMENT_HANDLERS = {
            commit: :process_commit,
            branch: :process_branch,
            checkout: :process_checkout,
            switch: :process_switch,
            merge: :process_merge,
            cherry_pick: :process_cherry_pick,
            acc_title: :process_acc_title,
          }.freeze
          private_constant :STATEMENT_HANDLERS

          # A backslash in a quoted string escapes the next character: `\n`
          # and the other control escapes become the control character,
          # anything else (`\"`, `\\`, `\x`) becomes itself.
          def self.unquote(captured)
            captured_text(captured).gsub(/\\(.)/m) do
              ESCAPES.fetch(Regexp.last_match(1), Regexp.last_match(1))
            end
          end

          # Mermaid trims every line of a directive's text.
          def self.directive_text(captured)
            captured_text(captured).strip.split("\n").map(&:strip).join("\n")
          end

          def initialize
            @current_branch = "main"
            @branches = { "main" => { order: 0, created_at: nil } }
            @commits = []
            @commit_counter = 0
          end

          def add_commit(options = {})
            @commit_counter += 1
            commit_id = options[:id] || "commit-#{@commit_counter}"
            commit = commit_identity(commit_id, options).merge(
              commit_semantics(options),
            )
            @commits << commit
            commit
          end

          def process(statements)
            Array(statements).each do |statement|
              process_statement(statement) if statement.is_a?(Hash)
            end
            self
          end

          def to_h
            {
              acc_title: acc_title,
              acc_description: acc_description,
              commits: commits,
              branches: branches.map { |name, info| branch_entry(name, info) },
            }
          end

          def extract_options(options)
            Array(options).each_with_object({}) do |option, result|
              next unless option.is_a?(Hash)

              OPTION_KEYS.each do |source, target|
                result[target] = option[source].to_s if option[source]
              end
              if option[:message]
                result[:message] = State.unquote(option[:message])
              end
            end
          end

          def commit_identity(commit_id, options)
            {
              id: commit_id,
              message: options[:message],
              type: options[:type] || "NORMAL",
              tag: options[:tag],
              branch_name: @current_branch,
              parent_ids: find_parents,
            }
          end

          def commit_semantics(options)
            {
              is_merge: options[:is_merge] || false,
              merge_branch: options[:merge_branch],
              is_cherry_pick: options[:is_cherry_pick] || false,
              cherry_pick_parent: options[:cherry_pick_parent],
            }
          end

          def add_branch(name, order = nil)
            return if @branches.key?(name)

            @branches[name] = {
              order: order,
              parent_branch: @current_branch,
              created_at: @commits.last&.fetch(:id),
            }
          end

          def checkout_branch(name)
            @current_branch = name
          end

          def merge_branch(branch_name, options = {})
            add_commit(
              options.merge(
                is_merge: true,
                merge_branch: branch_name,
              ),
            )
          end

          def cherry_pick(options = {})
            add_commit(
              options.merge(is_cherry_pick: true),
            )
          end

          private

          def process_statement(statement)
            entry = STATEMENT_HANDLERS.find { |key, _| statement.key?(key) }
            unless entry
              self.acc_description = State.directive_text(statement[:acc_descr])
              return
            end

            send(entry.last, statement.fetch(entry.first))
          end

          def process_commit(data)
            options = data.is_a?(Hash) ? extract_options(data[:options]) : {}
            add_commit(options)
          end

          def process_branch(data)
            options = data[:options]
            order = options.first[:order].to_i if options
            add_branch(State.unquote(data[:name]), order)
          end

          def process_checkout(data)
            checkout_branch(State.unquote(data[:branch]))
          end

          alias process_switch process_checkout

          def process_merge(data)
            branch = State.unquote(data[:branch])
            merge_branch(branch, extract_options(data[:options]))
          end

          def process_cherry_pick(data)
            cherry_pick(extract_options(data[:options]))
          end

          def process_acc_title(data)
            self.acc_title = State.directive_text(data)
          end

          def branch_entry(name, info)
            {
              name: name,
              order: info[:order],
              parent_branch: info[:parent_branch],
              created_at_commit: info[:created_at],
            }
          end

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
          State.new.process(stmts).to_h
        end
      end
    end
  end
end
