# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # Classes joined by unbranched chains of relations, ranked the way
      # PlantUML's layout engines rank them: every relation steps along one
      # axis, and an association class hangs off a junction node placed
      # between the two classes of its relation.
      #
      # A chain running along the rank axis (down the page, or across it
      # under `left to right direction`) steps one rank per dash past the
      # first, the way Graphviz reads a relation's length, and ranks are
      # shared by every chain, which sit side by side a node gap apart. When
      # any relation has a label every rank is halved and the label takes a
      # node of its own in the middle of its relation; every other rank a
      # relation crosses holds a 1px virtual node. The association class
      # shares its junction's rank.
      #
      # A single chain lying within one rank steps a node gap at a time and
      # the association class takes the next rank. {for} returns nil for any
      # other diagram, which keeps the grid.
      class RankChain
        # Gaps between rank extents (`rank`) and between neighbours in one
        # rank (`node`), measured on the pinned PlantUML references.
        GAPS = { smetana: { rank: 36.0, node: 18.0 },
                 dot: { rank: 60.0, node: 35.0 } }.freeze
        JUNCTION_SIZE = [16.0, 24.0].freeze
        REVERSED_DIRECTIONS = %i[up left].freeze
        # A label node is one 15px text line deep down the page and as wide
        # as the label across it, plus the engine's margin; measured on the
        # local PlantUML 1.2026.6 for every body length.
        LABEL_LINE = 15.0
        LABEL_MARGIN = { smetana: 4.0, dot: 2.0 }.freeze
        VIRTUAL_NODE = 1.0
        NON_RENDERED_SLOTS = %i[virtual label].freeze
        SMETANA = /\A!pragma[ \t]+layout[ \t]+smetana\z/i
        LEFT_TO_RIGHT = "left to right direction"
        private_constant :GAPS, :JUNCTION_SIZE, :REVERSED_DIRECTIONS,
                         :LABEL_LINE, :LABEL_MARGIN, :VIRTUAL_NODE, :SMETANA,
                         :LEFT_TO_RIGHT, :NON_RENDERED_SLOTS

        # @return [RankChain, nil]
        def self.for(diagram)
          fork = layout_only_fork(diagram)
          return fork if fork

          chain_for(diagram)
        end

        def self.chain_for(diagram)
          relations = diagram.relations
          chains = chains_of(diagram, relations)
          return unless chains

          owners = junction_owners(diagram, relations)
          return unless owners

          axis = chain_axis(diagram, relations, owners)
          return unless axis && shape_fits?(chains, owners, axis, diagram)
          return unless exact_classes?(diagram, all_names(chains), owners)

          new(chains, owners, axis, layout_of(diagram))
        end

        def self.layout_only_fork(diagram)
          relations = diagram.relations
          return unless forkable?(diagram, relations)

          root, leaves = fork_ends(relations)
          return unless root
          return unless exact_classes?(diagram, [root, *leaves], {})

          layout = layout_of(diagram)
          axis = chain_axis(diagram, relations, {})
          return unless axis == layout.fetch(:rank_axis)

          Fork.new(root, leaves, axis, layout.fetch(:engine))
        end

        def self.forkable?(diagram, relations)
          engine(diagram) == :smetana && fork_shape?(diagram) &&
            relations.size > 1 && relations.any?(&:layout_only?)
        end

        def self.fork_shape?(diagram)
          diagram.packages.empty? && diagram.notes.empty? &&
            diagram.junctions.empty?
        end

        def self.fork_ends(relations)
          lefts = relations.map(&:left)
          rights = relations.map(&:right)
          return [lefts.first, rights] if unique_fork?(lefts, rights)
          return [rights.first, lefts] if unique_fork?(rights, lefts)

          [nil, nil]
        end

        def self.unique_fork?(roots, leaves)
          roots.uniq.one? && leaves.uniq == leaves
        end

        def self.exact_classes?(diagram, names, owners)
          diagram.classes.map(&:name).sort == (names + owners.values).sort
        end

        # The relations in written order, cut into chains wherever one does
        # not start at the class the last ended on; nil when a class is on
        # two chains or twice on one.
        def self.chains_of(diagram, relations)
          return unless chainable?(diagram, relations)

          chains = relations.slice_when { |a, b| a.right != b.left }.to_a
          chains if unique_names?(chains)
        end

        def self.chainable?(diagram, relations)
          diagram.packages.empty? && diagram.notes.empty? && relations.any?
        end

        def self.unique_names?(chains)
          names = all_names(chains)
          names.uniq.size == names.size
        end

        def self.all_names(chains)
          chains.flat_map { |chain| names_of(chain) }
        end

        # @return [Array<String>] a chain's classes in order
        def self.names_of(chain)
          [chain.first.left, *chain.map(&:right)]
        end

        # Labels and side-by-side chains are measured only along the rank
        # axis and without association classes.
        def self.shape_fits?(chains, owners, axis, diagram)
          simple = chains.one? && chains.first.none?(&:label)
          simple || (owners.empty? && axis == layout_of(diagram)[:rank_axis])
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
          axes.first if axes.one?
        end

        def self.relation_axis(relation, diagram)
          across = %i[left right].include?(relation.direction)
          across = !across if left_to_right?(diagram)
          across ? :horizontal : :vertical
        end

        def self.left_to_right?(diagram)
          diagram.directives.include?(LEFT_TO_RIGHT)
        end

        # @return [Symbol] :smetana or :dot, the engine PlantUML lays out with
        def self.engine(diagram)
          smetana = diagram.directives.any? { |line| line.match?(SMETANA) }
          smetana ? :smetana : :dot
        end

        def self.layout_of(diagram)
          { engine: engine(diagram),
            rank_axis: left_to_right?(diagram) ? :horizontal : :vertical }
        end

        private_class_method :chains_of, :shape_fits?,
                             :junction_owners, :chain_axis, :relation_axis,
                             :left_to_right?, :layout_of, :exact_classes?,
                             :owners_by_relation, :valid_owners?, :chainable?,
                             :unique_names?, :all_names, :chain_for,
                             :layout_only_fork, :forkable?, :fork_shape?,
                             :fork_ends, :unique_fork?

        # A one-rank Smetana fork whose hidden edge still constrains the
        # visible nodes. The shared root is centred over (or beside) every
        # leaf, using the pinned engine's rank and node gaps.
        class Fork
          def initialize(root, leaves, axis, engine)
            @root = root
            @leaves = leaves
            @axis = axis
            @gaps = GAPS.fetch(engine)
          end

          def place(sizes, origin, _label_widths = {})
            [corners(sizes, origin), {}]
          end

          private

          def corners(sizes, origin)
            root_size = sizes.fetch(@root)
            spans = @leaves.map { |name| sizes.fetch(name).fetch(across_index) }
            breadth = total_breadth(spans)
            leaf_corners(spans, root_size, breadth, origin)
              .merge(@root => root_corner(root_size, breadth, origin))
          end

          def total_breadth(spans)
            spans.sum + (@gaps[:node] * (spans.size - 1))
          end

          def leaf_corners(spans, root_size, breadth, origin)
            cursor = leaf_cursor(root_size, breadth, origin)
            fixed = leaf_rank(root_size, origin)
            distribute(@leaves, spans, cursor, fixed, reverse: horizontal?)
          end

          def leaf_cursor(root_size, breadth, origin)
            root_breadth = root_size.fetch(across_index)
            available = [root_breadth, breadth].max - breadth
            origin.fetch(across_index) + (available / 2)
          end

          def leaf_rank(root_size, origin)
            origin.fetch(along_index) + root_size.fetch(along_index) +
              @gaps[:rank]
          end

          def root_corner(root_size, breadth, origin)
            corner = origin.dup
            extra = [breadth - root_size.fetch(across_index), 0].max
            corner[across_index] += extra / 2
            corner
          end

          def across_index
            horizontal? ? 1 : 0
          end

          def along_index
            1 - across_index
          end

          def horizontal?
            @axis == :horizontal
          end

          def distribute(names, spans, cursor, fixed, reverse: false)
            names.each_with_index.to_h do |name, index|
              corner = reverse ? [fixed, cursor] : [cursor, fixed]
              cursor += spans.fetch(index) + @gaps[:node]
              [name, corner]
            end
          end
        end

        attr_reader :chains, :owners, :axis

        # @param chains [Array<Array<Relation>>] the chains' relations in
        #   written order
        # @param owners [Hash{Integer => String}] association classes by the
        #   index of the relation they hang on
        # @param axis [Symbol] :vertical or :horizontal
        # @param layout [Hash] `:engine` and `:rank_axis`
        def initialize(chains, owners, axis, layout)
          @chains = chains
          @owners = owners
          @axis = axis
          @engine = layout.fetch(:engine)
          @gaps = GAPS.fetch(@engine)
          @ranked = axis == layout.fetch(:rank_axis)
          @halved = chains.flatten.any?(&:label)
          freeze
        end

        # @param sizes [Hash{String => Array(Float, Float)}] width and height
        #   of every class
        # @param origin [Array(Float, Float)] the top-left corner
        # @param label_widths [Hash{Integer => Float}] each label's width by
        #   the index of its relation
        # @return [Array(Hash, Hash)] each class's top-left corner by name,
        #   and each junction node as `[x, y, width, height]` by relation
        #   index
        def place(sizes, origin, label_widths = {})
          return place_flat(sizes, origin) unless ranked

          items = rank_items
          context = ranked_context(items, sizes, origin, label_widths)
          place_ranked(items, sizes, context)
        end

        private

        def ranked_context(items, sizes, origin, label_widths)
          spans = rank_spans(items, sizes, label_widths)
          { spans: spans, frames: chain_frames(items, sizes, origin),
            tops: rank_tops(spans, origin[along]) }
        end

        def place_ranked(items, sizes, context)
          items.each_with_object([{}, {}]) do |(chain, slot, rank), out|
            frame = context.fetch(:frames)[chain].merge(
              cursor: context.fetch(:tops)[rank],
              span: context.fetch(:spans)[rank],
            )
            place_slot(slot, sizes, frame, out)
          end
        end

        attr_reader :gaps, :ranked, :engine, :halved

        def place_flat(sizes, origin)
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
            cursor += span + gaps[:node]
          end
        end

        # Each class on the single chain, with a junction slot after every
        # relation that carries an association class.
        def chain_slots
          names = RankChain.names_of(chains.first)
          names.each_with_index.flat_map do |name, index|
            owner = owners[index]
            [[:class, name], *([[:junction, index, owner]] if owner)]
          end
        end

        # Every class and junction as `[chain, slot, rank]`, and every rank a
        # relation crosses as `[chain, [:virtual, index], rank]`, with
        # `[:label, index]` in the middle of a labelled one.
        def rank_items
          index = -1
          chains.each_with_index.flat_map do |chain, number|
            items, index = chain_rank_items(chain, number, index)
            items
          end
        end

        def chain_rank_items(chain, number, index)
          rank = 0
          items = [[number, [:class, chain.first.left], rank]]
          chain.each do |relation|
            index += 1
            rank += relation_items(relation, index, number, rank, items)
            items << [number, [:class, relation.right], rank]
          end
          [items, index]
        end

        # A junction's legs step one rank each.
        def relation_items(relation, index, number, rank, items)
          if (owner = owners[index])
            items << [number, [:junction, index, owner], rank + 1]
            return 2
          end

          steps = (relation.length - 1) * (halved ? 2 : 1)
          (1...steps).each do |step|
            node = relation.label && step == steps / 2 ? :label : :virtual
            items << [number, [node, index], rank + step]
          end
          steps
        end

        def rank_spans(items, sizes, label_widths)
          items.each_with_object({}) do |(_, slot, rank), spans|
            span = item_span(slot, sizes, label_widths)
            spans[rank] = [spans.fetch(rank, 0.0), span].max
          end
        end

        def item_span(slot, sizes, label_widths)
          case slot[0]
          when :virtual then VIRTUAL_NODE
          when :label then label_span(label_widths.fetch(slot[1]))
          else along_span(slot, sizes)
          end
        end

        def label_span(width)
          (axis == :vertical ? LABEL_LINE : width) + LABEL_MARGIN.fetch(engine)
        end

        def rank_tops(spans, start)
          separation = gaps[:rank] / (halved ? 2 : 1)
          (0..spans.keys.max).each_with_object([start]) do |rank, tops|
            tops << (tops.last + spans.fetch(rank) + separation)
          end
        end

        # Each chain's middle and breadth across the rank axis, chains a
        # node gap apart in written order.
        def chain_frames(items, sizes, origin)
          breadths = chain_breadths(items, sizes)
          edge = origin[across]
          chains.each_index.map do |chain|
            frame, edge = next_chain_frame(breadths.fetch(chain), edge)
            frame
          end
        end

        def chain_breadths(items, sizes)
          items.each_with_object({}) do |(chain, slot), widest|
            next if NON_RENDERED_SLOTS.include?(slot[0])

            widest[chain] = [widest.fetch(chain, 0.0),
                             slot_size(slot, sizes)[across]].max
          end
        end

        def next_chain_frame(breadth, edge)
          frame = { middle: edge + (breadth / 2), breadth: breadth }
          [frame, edge + breadth + gaps[:node]]
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
          return if NON_RENDERED_SLOTS.include?(slot[0])

          size = slot_size(slot, sizes)
          corner = slot_corner(size, frame)
          return out.first[slot[1]] = corner if slot[0] == :class

          place_junction(slot, sizes, corner, frame, out)
        end

        def place_junction(slot, sizes, corner, frame, out)
          places, junctions = out
          size = slot_size(slot, sizes)
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
