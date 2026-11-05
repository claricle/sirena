# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # How far apart PlantUML sets the rows of a class box's members,
      # measured against 1.2026.6. A row is 16.49 below the one before, with
      # 8 more between a field group and a method group; an empty group
      # keeps a gap of its own, unless a separator already splits the rows
      # into compartments of their own. A separator with a title is a row of
      # its own, drawn 3.5 low and followed 4 further down; one without a
      # title is no row but 8 of gap, its rule 6.95 under the row before.
      module MemberPitch
        extend self

        ROW = 16.48828125
        GROUP_GAP = 8.0
        TITLED_DROP = 3.5
        TITLED_EXTRA = 4.0
        BARE_GAP = 8.0
        BARE_RULE_DROP = 10.95
        private_constant :ROW, :GROUP_GAP, :TITLED_DROP, :TITLED_EXTRA,
                         :BARE_GAP, :BARE_RULE_DROP

        # @param kinds [Array<Symbol>] each row's kind, :separator included
        # @param titles [Array<String>] each row's text
        # @param gaps [Boolean] whether an empty field or method group keeps
        #   its gap; `hide` and `show` lines on members remove it
        # @return [Array(Array<Float>, Float)] each row's offset from the
        #   first row's baseline, and the extent the rows add to a box
        def layout(kinds, titles, gaps: true)
          cursor = gaps ? lead(kinds) : 0.0
          last = -ROW
          offsets = kinds.each_index.map do |index|
            cursor += GROUP_GAP if group_opens?(kinds, index)
            offset, cursor, last = place(kinds[index], titles[index], cursor,
                                         last)
            offset
          end
          [offsets, cursor + (gaps ? tail(kinds) : 0.0)]
        end

        # @return [Float] the gap above the rows of a box with methods and no
        #   fields: PlantUML draws the empty field compartment there
        def lead(kinds)
          return 0.0 if kinds.include?(:separator)

          kinds.include?(:method) && !kinds.include?(:field) ? GROUP_GAP : 0.0
        end

        # @return [Float] the gap below the rows of a box with fields and no
        #   methods: the empty method compartment
        def tail(kinds)
          return 0.0 if kinds.include?(:separator)

          kinds.include?(:field) && !kinds.include?(:method) ? GROUP_GAP : 0.0
        end

        private

        def group_opens?(kinds, index)
          index.positive? && kinds[index - 1] == :field &&
            kinds[index] == :method
        end

        def place(kind, title, cursor, last)
          return [cursor, cursor + ROW, cursor] unless kind == :separator
          return [last + BARE_RULE_DROP, cursor + BARE_GAP, last] if
            title.empty?

          [cursor + TITLED_DROP, cursor + ROW + TITLED_EXTRA, cursor]
        end
      end
    end
  end
end
