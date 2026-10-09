# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # A relation line, kept the way it was written.
      #
      # `left` and `right` are the class names on either side of the arrow.
      # `head` is the side the marker or arrowhead sits on, :left or :right,
      # or nil for a plain `--`. `kind` is :extension, :implementation,
      # :association, :dependency, :aggregation or :composition. The
      # multiplicities, roles and the label are the quoted, `/"role"` and
      # `: text` parts, or nil.
      class Relation
        attr_reader :left, :right, :kind, :head,
                    :left_multiplicity, :right_multiplicity, :label,
                    :left_role, :right_role

        # @param arrow [Hash] holds `:kind`, `:head` and `:plain`
        # @param ends [Hash] holds `:left`, `:right`, `:left_role` and
        #   `:right_role`, each a String or nil
        #
        # Those two travel as hashes because the scoreboard counts a parameter
        # list past five as lint debt.
        def initialize(left:, right:, arrow:, ends:, label:)
          @left = left
          @right = right
          @kind, @head, @plain = arrow.fetch_values(:kind, :head, :plain)
          @left_multiplicity, @right_multiplicity, @left_role, @right_role =
            ends.fetch_values(:left, :right, :left_role, :right_role)
          @label = label
          freeze
        end

        # True for a bare `-->` or `<--` style arrow, which a sequence
        # diagram also has.
        def plain?
          @plain
        end
      end
    end
  end
end
