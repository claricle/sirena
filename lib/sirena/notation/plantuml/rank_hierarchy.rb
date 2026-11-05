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
        RANK_GAP = 90.0
        NODE_GAP = 35.0
        SAME_RANK_GAP = 50.0
        BLOCK_GAP = 35.0
        LOOSE_COLUMNS = 2
        LOOSE_ROW_GAP = 60.0
        SIDEWAYS = %i[left right].freeze
        private_constant :RANK_GAP, :NODE_GAP, :SAME_RANK_GAP, :BLOCK_GAP,
                         :LOOSE_COLUMNS, :LOOSE_ROW_GAP, :SIDEWAYS

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
          corners = ranked_corners(rows_in_order, sizes, origin)
          corners.merge(loose_corners(sizes, corners, origin))
        end

        private

        def ranked_corners(rows, sizes, origin)
          lefts = centred_lefts(rows, sizes)
          shift = origin.first - lefts.values.min
          tops = row_tops(rows, sizes, origin.last)
          rows.flatten.to_h do |name|
            [name, [lefts.fetch(name) + shift, tops.fetch(name)]]
          end
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

        def row_tops(rows, sizes, start)
          cursor = start
          rows.each_with_object({}) do |row, tops|
            row.each { |name| tops[name] = cursor }
            cursor += row_height(row, sizes) + RANK_GAP
          end
        end

        def row_height(row, sizes)
          row.map { |name| sizes.fetch(name).last }.max
        end

        # Unrelated classes fill rows of two beside the hierarchy.
        def loose_corners(sizes, corners, origin)
          loose = declared - @ranks.keys
          return {} if loose.empty?

          edge = corners.map { |name, (x, _)| x + sizes.fetch(name).first }.max
          loose_rows(loose.each_slice(LOOSE_COLUMNS).to_a, sizes,
                     edge + BLOCK_GAP, origin.last)
        end

        def loose_rows(rows, sizes, left, top)
          cursor = top
          rows.each_with_object({}) do |row, corners|
            corners.merge!(row_corners(row, sizes, left, cursor))
            cursor += row_height(row, sizes) + LOOSE_ROW_GAP
          end
        end

        def row_corners(row, sizes, left, top)
          x = left
          row.to_h do |name|
            corner = [name, [x, top]]
            x += sizes.fetch(name).first + NODE_GAP
            corner
          end
        end
      end
    end
  end
end
