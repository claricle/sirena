# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # Classes joined by relations in a tree or a lattice, ranked the way
      # PlantUML's hierarchical layout ranks them: the class a relation's
      # glyph points away from sits one rank above the other (`A <|-- B` puts
      # A on top, `A <|-- B` written with `-up-` puts B on top), a
      # one-dash relation keeps both ends in one rank, and siblings fan out
      # side by side in one rank. Classes joined to nothing sit in a block to
      # the right of the hierarchy.
      #
      # {for} returns nil when the diagram has packages, association classes
      # or a relation cycle, which keeps the grid.
      class RankHierarchy
        RANK_GAP = 60.0
        NODE_GAP = 35.0
        SAME_RANK_GAP = 50.0
        BLOCK_GAP = 35.0
        # A label on a relation between neighbouring ranks takes a text row
        # of its own between them: 17 for one line, 15 more per further line.
        LABEL_ROW = 15.0
        LABEL_PAD = 2.0
        LOOSE_COLUMNS = 2
        SIDEWAYS = %i[left right].freeze
        private_constant :RANK_GAP, :LABEL_ROW, :LABEL_PAD, :NODE_GAP,
                         :SAME_RANK_GAP, :BLOCK_GAP,
                         :LOOSE_COLUMNS, :SIDEWAYS

        # @return [RankHierarchy, nil]
        def self.for(diagram)
          return unless fits?(diagram)

          ranks = rank_of(diagram)
          new(diagram, ranks) if ranks
        end

        def self.fits?(diagram)
          names = diagram.classes.map(&:name)
          diagram.packages.empty? && diagram.junctions.empty? &&
            diagram.relations.any? &&
            diagram.relations.all? { |relation| drawable?(relation, names) }
        end

        def self.drawable?(relation, names)
          ends = [relation.left, relation.right]
          !relation.layout_only? && ends.uniq.size == 2 &&
            ends.all? { |name| names.include?(name) }
        end

        # @return [Hash{String => Integer}, nil] each related class's rank
        def self.rank_of(diagram)
          related = diagram.relations.flat_map { |r| [r.left, r.right] }.uniq
          groups = same_rank_groups(diagram.relations, related)
          levels = group_levels(diagram.relations, groups)
          levels && related.to_h { |name| [name, levels.fetch(groups[name])] }
        end

        def self.group_levels(relations, groups)
          longest_paths(groups.values.uniq, deeper_edges(relations, groups))
        end

        # Union of the classes a one-dash or sideways relation keeps level.
        def self.same_rank_groups(relations, names)
          groups = names.to_h { |name| [name, name] }
          relations.select { |r| level?(r) }.each do |relation|
            keep = groups.fetch(relation.left)
            drop = groups.fetch(relation.right)
            groups.transform_values! { |group| group == drop ? keep : group }
          end
          groups
        end

        def self.level?(relation)
          SIDEWAYS.include?(relation.direction) ||
            (relation.direction.nil? && relation.length == 1)
        end

        # `[upper, lower]` group pairs for every relation that steps a rank.
        def self.deeper_edges(relations, groups)
          relations.reject { |r| level?(r) }.map do |relation|
            pair = [groups.fetch(relation.left), groups.fetch(relation.right)]
            relation.direction == :up ? pair.reverse : pair
          end
        end

        # Rank by longest path; nil when the relations loop.
        def self.longest_paths(groups, deeper)
          levels = groups.to_h { |group| [group, 0] }
          groups.size.times { return levels unless lowered?(levels, deeper) }
          nil
        end

        # Lowers every group that sits no deeper than its upper one; whether
        # any moved.
        def self.lowered?(levels, deeper)
          deeper.map do |upper, lower|
            next false if levels[lower] > levels[upper]

            levels[lower] = levels[upper] + 1
            true
          end.any?
        end

        # @param diagram [Diagram]
        # @param ranks [Hash{String => Integer}]
        def initialize(diagram, ranks)
          @diagram = diagram
          @ranks = ranks
          @order = ranks.keys.sort_by { |name| declared.index(name) }
        end

        # @param sizes [Hash{String => Array<Float>}] `[width, height]` by
        #   class name
        # @param origin [Array<Float>] top-left corner of the drawing
        # @return [Hash{String => Array<Float>}] each class's top-left corner
        def place(sizes, origin)
          rows = rows_in_order
          loose = loose_rows
          tops = rank_tops(rows, loose, sizes, origin.last)
          corners = ranked_corners(rows, sizes, origin.first, tops)
          corners.merge(loose_corners(loose, sizes, corners, tops))
        end

        private

        def ranked_corners(rows, sizes, left, tops)
          lefts = centred_lefts(rows, sizes)
          shift = left - lefts.values.min
          rows.each_with_index.flat_map do |row, rank|
            row.map do |name|
              [name, [lefts.fetch(name) + shift,
                      centred_top(tops.fetch(rank), sizes.fetch(name).last)]]
            end
          end.to_h
        end

        def declared
          @declared ||= @diagram.classes.map(&:name)
        end

        # Each rank's classes left to right: level-relation order first, then
        # the mean position of the class's upper neighbours.
        def rows_in_order
          depth = @ranks.values.max
          rows = (0..depth).map { [] }
          @order.each { |name| rows[@ranks.fetch(name)] << name }
          rows.each_with_index.with_object([]) do |(row, index), placed|
            placed << sorted_row(row, placed[index - 1], index)
          end
        end

        def sorted_row(row, above, index)
          keyed = row.each_with_index.sort_by do |name, position|
            [index.zero? ? 0 : mean_position(name, above), position]
          end.map(&:first)
          honour_level_order(keyed)
        end

        def mean_position(name, above)
          parents = neighbours(name, upper: true).filter_map do |parent|
            above.index(parent)
          end
          parents.empty? ? above.size : parents.sum.fdiv(parents.size)
        end

        # The classes one rank above `name`, or below it.
        def neighbours(name, upper:)
          @diagram.relations.filter_map do |relation|
            next if self.class.level?(relation)

            top, bottom = pair(relation)
            upper ? (top if bottom == name) : (bottom if top == name)
          end
        end

        def pair(relation)
          ends = [relation.left, relation.right]
          relation.direction == :up ? ends.reverse : ends
        end

        # A one-dash relation puts its written-first class on the left.
        def honour_level_order(row)
          constraints = @diagram.relations.select do |relation|
            self.class.level?(relation) && row.include?(relation.left)
          end
          constraints.each_with_object(row.dup) do |relation, ordered|
            move_before(ordered, *level_pair(relation))
          end
        end

        def move_before(ordered, left, right)
          return unless ordered.index(left) > ordered.index(right)

          ordered.delete(left)
          ordered.insert(ordered.index(right), left)
        end

        def level_pair(relation)
          ends = [relation.left, relation.right]
          relation.direction == :left ? ends.reverse : ends
        end

        # Left edges: rows packed left to right, then each class pulled
        # under its parents (and over its children) as far as its neighbours
        # allow.
        def centred_lefts(rows, sizes)
          lefts = {}
          rows.each { |row| pack(row, sizes, lefts) }
          rows.drop(1).each { |row| pull(row, sizes, lefts, upper: true) }
          rows.reverse.each { |row| pull(row, sizes, lefts, upper: false) }
          lefts
        end

        def pack(row, sizes, lefts)
          cursor = 0.0
          row.each do |name|
            lefts[name] = cursor
            cursor += sizes.fetch(name).first + gap_after(name, row)
          end
        end

        def gap_after(name, row)
          level = @diagram.relations.any? do |relation|
            self.class.level?(relation) && relation.left == name &&
              row.include?(relation.right)
          end
          level ? SAME_RANK_GAP : NODE_GAP
        end

        def pull(row, sizes, lefts, upper:)
          row.each_with_index do |name, index|
            wanted = wanted_centre(name, sizes, lefts, upper)
            next unless wanted

            floor = floor_for(row, index, sizes, lefts)
            lefts[name] = [wanted - (sizes.fetch(name).first / 2), floor].max
          end
        end

        # The leftmost the class at `index` may sit: clear of the one before.
        def floor_for(row, index, sizes, lefts)
          return -Float::INFINITY if index.zero?

          before = row[index - 1]
          lefts[before] + sizes.fetch(before).first + gap_after(before, row)
        end

        def wanted_centre(name, sizes, lefts, upper)
          others = neighbours(name, upper: upper)
          return if others.empty?

          centres = others.map { |other| centre(other, sizes, lefts) }
          centres.sum / centres.size
        end

        def centre(name, sizes, lefts)
          lefts.fetch(name) + (sizes.fetch(name).first / 2)
        end

        # Each rank's top and height: as tall as its tallest class, loose
        # ones included, the next rank a rank gap and the labels' room below.
        def rank_tops(rows, loose, sizes, start)
          cursor = start
          Array.new([rows.size, loose.size].max) do |rank|
            height = [rows, loose].map do |set|
              row_height(set.fetch(rank, []), sizes)
            end.max
            Top.new(cursor, height).tap do
              cursor += height + RANK_GAP + label_room(rows, rank)
            end
          end
        end

        Top = Struct.new(:at, :height)
        private_constant :Top

        # Classes of unequal height share their rank's middle.
        def centred_top(rank, height)
          rank.at + ((rank.height - height) / 2)
        end

        # The room the labels of the relations from rank `rank` down to the
        # next take: the tallest of them.
        def label_room(rows, rank)
          lines = rows[rank + 1] && @diagram.relations.filter_map do |relation|
            label_lines(relation, rows[rank], rows[rank + 1])
          end&.max
          lines ? LABEL_PAD + (lines * LABEL_ROW) : 0.0
        end

        def label_lines(relation, row, below)
          top, bottom = pair(relation)
          return if self.class.level?(relation) || relation.label.to_s.empty?
          return unless row.include?(top) && below.include?(bottom)

          relation.label.split('\\n').size
        end

        def row_height(row, sizes)
          row.map { |name| sizes.fetch(name).last }.max || 0.0
        end

        # Unrelated classes fill rows of two beside the hierarchy, a row to
        # a rank.
        def loose_rows
          (declared - @ranks.keys).each_slice(LOOSE_COLUMNS).to_a
        end

        # The first column sits right of the hierarchy's ranks that hold a
        # loose class and centres its classes on one another; the rest follow
        # their neighbour.
        def loose_corners(loose, sizes, corners, tops)
          return {} if loose.empty?

          left = loose_left(loose, sizes, corners)
          starts = first_columns(loose, sizes, left)
          loose.each_index.map do |rank|
            row_corners(loose[rank], sizes, tops.fetch(rank), starts[rank])
          end.reduce(:merge)
        end

        def first_columns(loose, sizes, left)
          widths = loose.map { |row| sizes.fetch(row.first).first }
          widths.map { |width| left + ((widths.max - width) / 2) }
        end

        def loose_left(loose, sizes, corners)
          beside = corners.select { |name, _| @ranks.fetch(name) < loose.size }
          beside.map { |name, (x, _)| x + sizes.fetch(name).first }.max +
            BLOCK_GAP
        end

        def row_corners(row, sizes, rank, first)
          x = first
          row.to_h do |name|
            width, height = sizes.fetch(name)
            corner = [name, [x, centred_top(rank, height)]]
            x += width + NODE_GAP
            corner
          end
        end
      end
    end
  end
end
