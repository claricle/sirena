# frozen_string_literal: true

module Sirena
  module Parser
    module Native
      # Reads captures out of a native parse tree.
      module Text
        module_function

        # An empty capture is an Array in the tree, like Parslet's.
        #
        # @return [String]
        def of(capture)
          capture.is_a?(Array) ? "" : capture.to_s
        end

        # @return [Boolean] whether the capture matched no characters
        def empty?(capture)
          of(capture).empty?
        end

        # The tree's statement list, whatever shape one statement gives.
        #
        # @return [Array<Hash>]
        def items(tree)
          [tree].flatten(1).grep(Hash)
        end
      end
    end
  end
end
