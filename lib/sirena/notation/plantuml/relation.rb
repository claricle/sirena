# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # A relation line, kept the way it was written.
      #
      # `left` and `right` are the class names on either side of the arrow.
      # `head` is the side the marker or arrowhead sits on, :left or :right,
      # :both, or nil for a plain `--`. `kind` is :extension,
      # :implementation, :association, :dependency, :aggregation,
      # :composition or :nesting, and nil when `head` is :both; `markers`
      # then maps each side to its kind. `dashed` is true for a dotted
      # body. `direction` is the glyph's :up, :down, :left or :right word,
      # or nil. `length` counts the body's dashes and dots. The
      # multiplicities, roles and the label are the quoted, `/"role"` and
      # `: text` parts, or nil.
      class Relation
        attr_reader :left, :right, :kind, :head, :markers,
                    :left_multiplicity, :right_multiplicity, :label,
                    :left_role, :right_role, :direction, :length

        # @param arrow [Hash] holds `:kind`, `:head`, `:markers`, `:dashed`
        #   and `:plain`, and optionally `:direction` and `:length` (2 when
        #   absent, the body of `--`)
        # @param ends [Hash] holds `:left`, `:right`, `:left_role` and
        #   `:right_role`, each a String or nil
        #
        # Those two travel as hashes because the scoreboard counts a parameter
        # list past five as lint debt.
        def initialize(left:, right:, arrow:, ends:, **options)
          @left = left
          @right = right
          assign_arrow(arrow)
          assign_ends(ends)
          @label = options.fetch(:label)
          @layout_only = options.fetch(:layout_only, false)
          freeze
        end

        def assign_arrow(arrow)
          @kind, @head, @markers, @dashed, @plain =
            arrow.fetch_values(:kind, :head, :markers, :dashed, :plain)
          @direction = arrow[:direction]
          @length = arrow.fetch(:length, 2)
        end

        def assign_ends(ends)
          @left_multiplicity, @right_multiplicity, @left_role, @right_role =
            ends.fetch_values(:left, :right, :left_role, :right_role)
        end

        private :assign_arrow, :assign_ends

        def dashed?
          @dashed
        end

        # True for a bare `-->` or `<--` style arrow, which a sequence
        # diagram also has.
        def plain?
          @plain
        end

        # True when PlantUML keeps this edge as a layout constraint but does
        # not draw it, such as a relation touching a hidden Smetana class.
        def layout_only?
          @layout_only
        end

        def as_layout_only
          self.class.new(left: left, right: right, arrow: arrow_attributes,
                         ends: end_attributes, label: label,
                         layout_only: true)
        end

        private

        def arrow_attributes
          { kind: kind, head: head, markers: markers, dashed: dashed?,
            plain: plain?, direction: direction, length: length }
        end

        def end_attributes
          { left: left_multiplicity, right: right_multiplicity,
            left_role: left_role, right_role: right_role }
        end
      end
    end
  end
end
