# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # The multiplicity and `/"role"` texts at a relation's two ends, in the
      # order PlantUML draws them.
      #
      # PlantUML links its first class to its second; an `up` or `left` word
      # swaps which written class is first. Smetana draws the second end's
      # multiplicity, the first's, the first's role, then the second's role;
      # dot draws the first end's multiplicity and role, then the second's.
      # Each text is creole: a leading `#` makes it a numbered item, drawn as
      # a `1.` text beside the rest.
      class EndTexts
        ORDERS = {
          smetana: [%i[second multiplicity], %i[first multiplicity],
                    %i[first role], %i[second role]],
          dot: [%i[first multiplicity], %i[first role],
                %i[second multiplicity], %i[second role]],
        }.freeze
        NUMBERED_ITEM = /\A#+[ \t]*(?=\S)/
        NUMBER = "1."
        private_constant :ORDERS, :NUMBERED_ITEM, :NUMBER

        # @return [Array<Symbol>] the written sides (:left, :right) of the
        #   link's first and second class
        attr_reader :sides

        # @param relation [Relation]
        # @param engine [Symbol] :smetana or :dot
        def initialize(relation, engine)
          @relation = relation
          @engine = engine
          @sides = if %i[up left].include?(relation.direction)
                     %i[right left]
                   else
                     %i[left right]
                   end
          freeze
        end

        # @return [Array<Hash>] each present text as `:side` (:left or
        #   :right), `:kind` (:multiplicity or :role) and `:pieces`, the
        #   Strings drawn side by side
        def entries
          entries = ORDERS.fetch(@engine).filter_map do |position, kind|
            side = position == :first ? sides.first : sides.last
            content = @relation.public_send(:"#{side}_#{kind}")
            entry(side, kind, content) if content
          end
          ordinary, qualifiers = entries.partition do |entry|
            entry[:kind] != :qualifier
          end
          ordinary + qualifiers
        end

        private

        def entry(side, kind, content)
          qualifier = content.start_with?("[") && content.end_with?("]")
          content = content[1...-1] if qualifier
          lines = content.split("\\n")
          { side: side, kind: (qualifier ? :qualifier : kind),
            pieces: pieces(lines), multiline: lines.size > 1 }
        end

        def pieces(lines)
          return lines if lines.size > 1

          content = lines.first
          marker = content[NUMBERED_ITEM]
          marker ? [NUMBER, content.delete_prefix(marker)] : [content]
        end
      end
    end
  end
end
