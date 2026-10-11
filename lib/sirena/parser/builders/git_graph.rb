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
            id: :id, type: :type,
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

          def initialize(main_branch_name = "main")
            @current_branch = main_branch_name
            @branches = {
              main_branch_name => { order: 0, created_at: nil },
            }
            @commits = []
            @commit_counter = 0
          end

          def add_commit(options = {})
            @commit_counter += 1
            commit_id = options[:id] || "commit-#{@commit_counter}"
            validate_commit_id!(commit_id, options)
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
              main_branch_name: branches.first.first,
              commits: commits,
              branches: branches.map { |name, info| branch_entry(name, info) },
            }
          end

          def extract_options(options)
            Array(options).each_with_object({}) do |option, result|
              next unless option.is_a?(Hash)

              OPTION_KEYS.each do |source, target|
                assign_option(result, option, source, target)
              end
              assign_tag(result, option) if option.key?(:tag)
              if option[:message]
                result[:message] = State.unquote(option[:message])
              end
            end
          end

          def assign_option(result, option, source, target)
            value = option[source]&.to_s
            return if value.nil?

            result[target] = value
          end

          def assign_tag(result, option)
            value = option[:tag]&.to_s
            value = "" if value == '""'
            result[:tags] ||= []
            result[:tags] << value
            result[:tag] = value unless value.empty?
          end

          def commit_identity(commit_id, options)
            {
              id: commit_id,
              message: options[:message],
              type: options[:type] || "NORMAL",
              tag: options[:tag],
              tags: options.fetch(:tags, []),
              branch_name: @current_branch,
              parent_ids: options[:parent_ids] || find_parents,
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
              created_at: branch_tip(@current_branch),
            }
          end

          def checkout_branch(name)
            unless @branches.key?(name)
              raise Parser::ParseError, "Unknown branch: #{name}."
            end

            @current_branch = name
          end

          def merge_branch(branch_name, options = {})
            validate_merge!(branch_name)
            source_tip = branch_tip(branch_name)
            current_tip = branch_tip(@current_branch)
            add_commit(
              options.merge(
                is_merge: true,
                merge_branch: branch_name,
                parent_ids: [current_tip, source_tip].compact,
              ),
            )
          end

          def cherry_pick(options = {})
            validate_cherry_pick!(options)
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
            name = State.unquote(data[:name])
            add_branch(name, order)
            checkout_branch(name)
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
            tip = branch_tip(@current_branch)
            tip ? [tip] : []
          end

          def branch_tip(name)
            commit = @commits.reverse.find { |item| item[:branch_name] == name }
            commit&.fetch(:id) || @branches.fetch(name).fetch(:created_at)
          end

          def validate_commit_id!(commit_id, options)
            return unless options[:is_merge]
            return unless @commits.any? { |item| item[:id] == commit_id }

            raise Parser::ParseError, "Commit id #{commit_id} already exists."
          end

          def validate_merge!(branch_name)
            unless @branches.key?(branch_name)
              raise Parser::ParseError, "Unknown branch: #{branch_name}."
            end
            if branch_name == @current_branch
              raise Parser::ParseError, "Cannot merge a branch into itself."
            end

            source_tip = branch_tip(branch_name)
            current_tip = branch_tip(@current_branch)
            return if source_tip && source_tip != current_tip

            raise Parser::ParseError,
                  "Branch #{branch_name} has no new commits to merge."
          end

          def validate_cherry_pick!(options)
            target = @commits.find { |item| item[:id] == options[:id] }
            unless target
              raise Parser::ParseError,
                    "Unknown cherry-pick commit: #{options[:id]}."
            end

            parent = options[:cherry_pick_parent]
            valid_parent = parent && target[:parent_ids].include?(parent)
            return unless target[:is_merge] && !valid_parent

            raise Parser::ParseError,
                  "Cherry-picking merge commit #{target[:id]} requires " \
                  "a valid parent."
          end
        end

        def self.build(statements, main_branch_name: "main")
          State.new(main_branch_name).process(statements).to_h
        end

        # Statement handlers
        rule(statements: subtree(:stmts)) do
          GitGraph.build(stmts)
        end
      end
    end
  end
end
