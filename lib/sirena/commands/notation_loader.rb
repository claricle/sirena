# frozen_string_literal: true

module Sirena
  module Commands
    # Loads the files named by `--require`, exactly as `ruby -r` would: a
    # notation registers itself while its file loads.
    module NotationLoader
      module_function

      # @param features [Array<String>, String, nil] feature names or paths
      # @return [void]
      # @raise [ArgumentError] when a feature cannot be loaded
      def load_all(features)
        Array(features).each do |feature|
          require feature
        rescue LoadError
          raise ArgumentError, "Cannot load notation: #{feature}"
        end
      end
    end
  end
end
