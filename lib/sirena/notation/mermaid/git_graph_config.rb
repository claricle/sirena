# frozen_string_literal: true

require "psych"

module Sirena
  module Notation
    module Mermaid
      # Reads the one Mermaid init setting that changes Git Graph semantics.
      module GitGraphConfig
        INIT = /\A%%\{\s*init\s*:\s*(?<payload>.*)\s*\}%%\z/im
        private_constant :INIT

        module_function

        def main_branch_name(directives)
          directives.reverse_each do |directive|
            name = branch_name(directive)
            return name if name
          end
          "main"
        end

        def branch_name(directive)
          match = INIT.match(directive)
          return unless match

          config = Psych.safe_load(
            match[:payload], permitted_classes: [],
            permitted_symbols: [], aliases: false
          )
          name = config.dig("gitGraph", "mainBranchName") if
            config.is_a?(Hash)
          name.to_s unless name.nil? || name.to_s.empty?
        rescue Psych::Exception
          nil
        end
        private_class_method :branch_name
      end
    end
  end
end
