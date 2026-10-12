# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # Classes joined by one unbranched chain of relations, ranked the way
      # PlantUML's layout engines rank them: every relation steps along one
      # axis, and an association class hangs off a junction node placed
      # between the two classes of its relation.
      #
      # A chain running along the rank axis (down the page, or across it
      # under `left to right direction`) steps a rank gap at a time and the
      # association class shares its junction's rank. A chain lying within
      # one rank steps a node gap at a time and the association class takes
      # the next rank. {for} returns nil for any other diagram, which keeps
      # the grid.
      class RankChain
        # Gaps between rank extents (`rank`) and between neighbours in one
        # rank (`node`), measured on the pinned PlantUML references.
        GAPS = { smetana: { rank: 36.0, node: 18.0 },
                 dot: { rank: 60.0, node: 35.0 } }.freeze
        JUNCTION_SIZE = [16.0, 24.0].freeze
        REVERSED_DIRECTIONS = %i[up left].freeze
        SMETANA = /\A!pragma[ \t]+layout[ \t]+smetana\z/i
        LEFT_TO_RIGHT = "left to right direction"
        private_constant :GAPS, :JUNCTION_SIZE, :REVERSED_DIRECTIONS,
                         :SMETANA, :LEFT_TO_RIGHT

        # @return [RankChain, nil]
        def self.for(diagram)
          relations = diagram.relations
          return unless chain?(diagram, relations)

          owners = junction_owners(diagram, relations)
          axis = owners && chain_axis(diagram, relations, owners)
          return unless axis

          names = [relations.first.left, *relations.map(&:right)]
          return unless exact_classes?(diagram, names, owners)

          new(names, owners, axis, layout_of(diagram))
        end

        def self.exact_classes?(diagram, names, owners)
          diagram.classes.map(&:name).sort == (names + owners.values).sort
        end

        def self.chain?(diagram, relations)
          plain_diagram?(diagram) && unlabelled_relations?(relations) &&
            linked_chain?(relations) && unique_chain?(relations)
        end

        def self.plain_diagram?(diagram)
          diagram.packages.empty? && diagram.notes.empty?
        end

        def self.unlabelled_relations?(relations)
          relations.any? && relations.none?(&:label)
        end

        def self.linked_chain?(relations)
          relations.each_cons(2).all? do |first, second|
            first.right == second.left
          end
        end

        def self.unique_chain?(relations)
          [relations.first.left, *relations.map(&:right)].uniq.size ==
            relations.size + 1
        end

        # The owner of each junction keyed by its relation's index, or nil
        # when a relation carries two or an owner is also on the chain.
        def self.junction_owners(diagram, relations)
          owners = owners_by_relation(diagram.junctions, relations)
          names = relations.flat_map { |r| [r.left, r.right] }
          return unless valid_owners?(owners, diagram.junctions, names)

          owners
        end

        def self.owners_by_relation(junctions, relations)
          junctions.to_h do |junction|
            pair = [junction.from, junction.to].sort
            index = relations.index { |r| [r.left, r.right].sort == pair }
            [index, junction.owner]
          end
        end

        def self.valid_owners?(owners, junctions, names)
          owners.size == junctions.size &&
            owners.values.uniq.size == owners.size &&
            !owners.values.intersect?(names)
        end

        # :vertical or :horizontal when every relation steps the same way.
        # An `up` or `left` word reverses a plain relation, which has no
        # pinned reference yet, so only a relation with a junction takes
        # one; PlantUML keeps that relation's classes in written order.
        def self.chain_axis(diagram, relations, owners)
          axes = relations.each_with_index.map do |relation, index|
            reversed = REVERSED_DIRECTIONS.include?(relation.direction)
            return if reversed && !owners.key?(index)

            relation_axis(relation, diagram)
          end.uniq
          axes.first if axes.one? && texts_fit?(axes.first, relations)
        end

        def self.relation_axis(relation, diagram)
          across = %i[left right].include?(relation.direction)
          across = !across if left_to_right?(diagram)
          across ? :horizontal : :vertical
        end

        # End texts are measured only beside a vertical relation.
        def self.texts_fit?(axis, relations)
          axis == :vertical || relations.all? do |relation|
            [relation.left_multiplicity, relation.right_multiplicity,
             relation.left_role, relation.right_role].none?
          end
        end

        def self.left_to_right?(diagram)
          diagram.directives.include?(LEFT_TO_RIGHT)
        end

        def self.layout_of(diagram)
          smetana = diagram.directives.any? { |line| line.match?(SMETANA) }
          { engine: smetana ? :smetana : :dot,
            rank_axis: left_to_right?(diagram) ? :horizontal : :vertical }
        end

        private_class_method :chain?, :junction_owners, :chain_axis,
                             :relation_axis, :texts_fit?, :left_to_right?,
                             :layout_of, :exact_classes?, :plain_diagram?,
                             :unlabelled_relations?, :linked_chain?,
                             :unique_chain?, :owners_by_relation,
                             :valid_owners?

        attr_reader :names, :owners, :axis

        # @param names [Array<String>] the chain's classes in order
        # @param owners [Hash{Integer => String}] association classes by the
        #   index of the relation they hang on
        # @param axis [Symbol] :vertical or :horizontal
        # @param layout [Hash] `:engine` and `:rank_axis`
        def initialize(names, owners, axis, layout)
          @names = names
          @owners = owners
          @axis = axis
          @gaps = GAPS.fetch(layout.fetch(:engine))
          @ranked = axis == layout.fetch(:rank_axis)
          freeze
        end

        # @param sizes [Hash{String => Array(Float, Float)}] width and height
        #   of every class
        # @param origin [Array(Float, Float)] the top-left corner
        # @return [Array(Hash, Hash)] each class's top-left corner by name,
        #   and each junction node as `[x, y, width, height]` by relation
        #   index
        def place(sizes, origin)
          slots = chain_slots
          breadth = slots.map { |slot| slot_size(slot, sizes)[across] }.max
          frame = { middle: origin[across] + (breadth / 2), breadth: breadth }
          place_slots(slots, sizes, frame, origin[along])
        end

        def place_slots(slots, sizes, frame, cursor)
          slots.each_with_object([{}, {}]) do |slot, out|
            span = along_span(slot, sizes)
            place_slot(slot, sizes, frame.merge(cursor: cursor, span: span),
                       out)
            cursor += span + (ranked ? gaps[:rank] : gaps[:node])
          end
        end

        private

        attr_reader :gaps, :ranked

        # Each class on the chain, with a junction slot after every relation
        # that carries an association class.
        def chain_slots
          names.each_with_index.flat_map do |name, index|
            owner = owners[index]
            [[:class, name], *([[:junction, index, owner]] if owner)]
          end
        end

        def along
          axis == :vertical ? 1 : 0
        end

        def across
          1 - along
        end

        def slot_size(slot, sizes)
          slot[0] == :class ? sizes.fetch(slot[1]) : JUNCTION_SIZE
        end

        # On a ranked chain the owner shares its junction's rank, so that
        # rank is as deep as the deeper of the two.
        def along_span(slot, sizes)
          span = slot_size(slot, sizes)[along]
          return span unless ranked && slot[0] == :junction

          [span, sizes.fetch(slot[2])[along]].max
        end

        def place_slot(slot, sizes, frame, out)
          size = slot_size(slot, sizes)
          corner = slot_corner(size, frame)
          places, junctions = out
          return places[slot[1]] = corner if slot[0] == :class

          junctions[slot[1]] = [*corner, *size]
          places[slot[2]] = owner_corner(corner, sizes.fetch(slot[2]), frame)
          places
        end

        def slot_corner(size, frame)
          corner_at(
            frame[:cursor] + ((frame[:span] - size[along]) / 2),
            frame[:middle] - (size[across] / 2),
          )
        end

        def corner_at(along_position, across_position)
          if axis == :vertical
            [across_position, along_position]
          else
            [along_position, across_position]
          end
        end

        # Centred on the junction along the chain: beside it in its rank on
        # a ranked chain, else one rank past the chain.
        def owner_corner(junction, owner, frame)
          centre = junction[along] + (JUNCTION_SIZE[along] / 2)
          offset = owner_offset(junction, frame)
          corner_at(centre - (owner[along] / 2), offset)
        end

        def owner_offset(junction, frame)
          return ranked_owner_offset(junction) if ranked

          frame[:middle] + (frame[:breadth] / 2) + gaps[:rank]
        end

        def ranked_owner_offset(junction)
          junction[across] + JUNCTION_SIZE[across] + gaps[:node]
        end
      end
    end
  end
end
