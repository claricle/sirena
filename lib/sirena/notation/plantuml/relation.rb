# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # A relation line, kept the way it was written.
      #
      # `left` and `right` are the class names on either side of the arrow.
      # `head` is the side the marker or arrowhead sits on, :left or :right,
      # or nil for a plain `--`. `kind` is :extension, :implementation,
      # :association, :aggregation or :composition. The multiplicities and
      # the label are the quoted and `: text` parts, or nil.
      class Relation
        attr_reader :left, :right, :kind, :head,
                    :left_multiplicity, :right_multiplicity, :label

        # @param arrow [Hash] holds `:kind` and `:head`
        # @param multiplicities [Hash] holds `:left` and `:right`, each a
        #   String or nil
        #
        # Those two travel as hashes because the scoreboard counts a parameter
        # list past five as lint debt.
        def initialize(left:, right:, arrow:, multiplicities:, label:)
          @left = left
          @right = right
          @kind, @head = arrow.fetch_values(:kind, :head)
          @left_multiplicity, @right_multiplicity =
            multiplicities.fetch_values(:left, :right)
          @label = label
          freeze
        end
      end
    end
  end
end
