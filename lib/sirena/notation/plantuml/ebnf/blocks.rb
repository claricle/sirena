# frozen_string_literal: true

require_relative "model"

module Sirena
  module Notation
    module PlantUML
      module Ebnf
        # Sized pieces of a railroad diagram. Each knows its width, its
        # height and `baseline`, the y of its rail from its top, and draws
        # itself, rails included, at a position.
        module Blocks
          RADIUS = 10.0
          GAP = 10.0
          SIDE = 20.0
          WORD_HEIGHT = 26.0

          # A block's shared shape.
          class Block
            attr_reader :width, :height, :baseline

            def initialize(width, height, baseline)
              @width = width
              @height = height
              @baseline = baseline
            end
          end

          # A terminal, nonterminal or special sequence in a box.
          class Word < Block
            def initialize(pen, text, style)
              super(pen.text_width(text) + 20, WORD_HEIGHT, WORD_HEIGHT / 2)
              @text = text
              @style = style
            end

            def draw(pen, left, top)
              pen.rect(left, top, width, height, **@style)
              pen.text(@text, left + (width / 2), top + baseline,
                       anchor: "middle")
            end
          end

          # Nothing: just the rail, for the empty branch of an optional.
          class Gap < Block
            def initialize
              super(0.0, 0.0, 0.0)
            end

            def draw(_pen, _left, _top); end
          end

          # Blocks one after another along the rail.
          class Row < Block
            def initialize(items)
              ascent = items.map(&:baseline).max
              descent = items.map { |item| item.height - item.baseline }.max
              super(items.sum(&:width) + (GAP * (items.size - 1)),
                    ascent + descent, ascent)
              @items = items
            end

            def draw(pen, left, top)
              rail = top + baseline
              lefts = lefts_from(left)
              @items.each_with_index do |item, index|
                item.draw(pen, lefts[index], rail - item.baseline)
              end
              join(pen, lefts, rail)
            end

            private

            def lefts_from(left)
              @items.each_with_object([left]) do |item, lefts|
                lefts << (lefts.last + item.width + GAP)
              end
            end

            def join(pen, lefts, rail)
              @items.each_cons(2).with_index do |(item, _), index|
                pen.line(lefts[index] + item.width, rail, lefts[index + 1],
                         rail)
              end
            end
          end

          # Alternatives stacked, the first on the rail.
          class Stack < Block
            def initialize(branches)
              @branches = branches
              @tops = tops_of(branches)
              super(branches.map(&:width).max + (2 * SIDE),
                    @tops.last + branches.last.height,
                    branches.first.baseline)
            end

            def draw(pen, left, top)
              rail = top + baseline
              @branches.each_with_index do |branch, index|
                level = top + @tops[index] + branch.baseline
                draw_branch(pen, branch, left, [rail, level])
              end
            end

            private

            def tops_of(branches)
              branches.each_with_object([0.0]) do |branch, tops|
                tops << (tops.last + branch.height + GAP)
              end.first(branches.size)
            end

            def draw_branch(pen, branch, left, (rail, level))
              inner = left + SIDE + slack(branch)
              branch.draw(pen, inner, level - branch.baseline)
              turned = level != rail
              feeds(pen, [[left, inner], [left + width, inner + branch.width]],
                    level, turned)
              turns(pen, left, rail, level) if turned
            end

            def slack(branch)
              (width - (2 * SIDE) - branch.width) / 2
            end

            def feeds(pen, spans, level, turned)
              spans.each { |edge, from| feed(pen, edge, from, level, turned) }
            end

            # The rail from a branch's end out to the stack's edge, stopping
            # short of it where a turn takes over.
            def feed(pen, edge, from, level, turned)
              inset = turned ? RADIUS : 0.0
              pen.line(from, level, edge + (from > edge ? inset : -inset),
                       level)
            end

            def turns(pen, left, rail, level)
              pen.path(corner(left, rail, level, RADIUS))
              pen.path(corner(left + width, rail, level, -RADIUS))
            end

            def corner(edge, rail, level, run)
              [[:move, edge, rail], [:line, edge, level - RADIUS],
               [:curve, edge, level, edge + run, level]]
            end
          end

          # A block that may be taken again, by a line looping back under it.
          class Loop < Block
            BACK = 26.0

            def initialize(item)
              super(item.width + (2 * SIDE), item.height + BACK,
                    item.baseline)
              @item = item
            end

            def draw(pen, left, top)
              rail = top + baseline
              @item.draw(pen, left + SIDE, top)
              rails(pen, left, rail)
              back(pen, left, rail, top + @item.height + (BACK / 2))
            end

            private

            def rails(pen, left, rail)
              pen.line(left, rail, left + SIDE, rail)
              pen.line(left + SIDE + @item.width, rail, left + width, rail)
            end

            def back(pen, left, rail, level)
              near = left + RADIUS
              far = left + width - RADIUS
              pen.path([[:move, far, rail], [:line, far, level - RADIUS],
                        [:curve, far, level, far - RADIUS, level],
                        [:line, near + RADIUS, level],
                        [:curve, near, level, near, level - RADIUS],
                        [:line, near, rail]])
              arrow(pen, (near + far) / 2, level)
            end

            def arrow(pen, centre, level)
              pen.polygon([[centre - 4, level], [centre + 3, level - 4],
                           [centre + 3, level + 4]])
            end
          end
        end
      end
    end
  end
end
