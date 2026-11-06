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
          RADIUS = 12.0
          GAP = 10.0
          SIDE = 2 * RADIUS
          WORD_HEIGHT = 26.4883
          WORD_PAD = 10.0
          TEXT = 14
          # Where a heading arrow sits along a rail, as PlantUML places it.
          HEAD_AT = 0.4
          HEAD_BACK = 2.0
          HEAD_MIN = 11.0

          # An arrowhead on the rail at `y`, pointing right from `tail`.
          def self.heading(pen, tail, level)
            pen.polygon([[tail, level - 3], [tail + 6, level],
                         [tail, level + 3]])
          end

          # Where the arrowhead sits on a rail of `length`, from its start.
          def self.heading_at(length)
            [(HEAD_AT * length) - HEAD_BACK, HEAD_MIN].max
          end

          # The rail's bends, as the PlantUML JAR draws them: cubic curves
          # whose handles run three quarters of the radius.
          module Curves
            module_function

            # A turn from a horizontal rail into a vertical one.
            def upright(from_x, from_y, run, rise, radius)
              handle = 0.75 * radius
              [:bezier, from_x + ((run <=> 0) * handle), from_y,
               from_x + run, from_y + rise - ((rise <=> 0) * handle),
               from_x + run, from_y + rise]
            end

            # A turn from a vertical rail into a horizontal one.
            def level(from_x, from_y, run, rise, radius)
              handle = 0.75 * radius
              [:bezier, from_x, from_y + ((rise <=> 0) * handle),
               from_x + run - ((run <=> 0) * handle), from_y + rise,
               from_x + run, from_y + rise]
            end

            # From the rail at an edge down to a branch's level, `run`
            # being the radius toward the branch (negative on the right).
            # A bypass turns once, in an S; any other branch turns, runs
            # straight and turns again.
            def drop(edge, rail, level, run, smooth: false)
              top = smooth ? (rail + level) / 2 : rail + RADIUS
              bottom = smooth ? top : level - RADIUS
              [[:move, edge, rail],
               upright(edge, rail, run, top - rail, RADIUS),
               *(smooth ? [] : [[:line, edge + run, bottom]]),
               level(edge + run, bottom, run, level - bottom, RADIUS)]
            end
          end

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
              super(pen.text_width(text, size: TEXT) + WORD_PAD, WORD_HEIGHT,
                    WORD_HEIGHT / 2)
              @text = text
              @style = style
            end

            def draw(pen, left, top)
              pen.rect(left, top, width, height, **@style)
              pen.text(@text, left + (width / 2), top + baseline,
                       anchor: "middle", size: TEXT)
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
              @smooth = branches.first.is_a?(Gap)
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
              heading(pen, left, rail)
            end

            private

            # A skipped branch leaves the rail bare, so it carries the
            # arrow that shows which way the rail runs.
            def heading(pen, left, rail)
              return unless @branches.first.is_a?(Gap)

              Blocks.heading(pen, left + Blocks.heading_at(width), rail)
            end

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
              inset = turned ? SIDE : 0.0
              pen.line(from, level, edge + (from > edge ? inset : -inset),
                       level)
            end

            def turns(pen, left, rail, level)
              pen.path(Curves.drop(left, rail, level, RADIUS, smooth: @smooth))
              pen.path(Curves.drop(left + width, rail, level, -RADIUS,
                                   smooth: @smooth))
            end
          end

          # A block that may be taken again, by a line looping back over it.
          class Loop < Block
            BACK = 14.0
            INSET = 20.0
            TURN = 8.0

            def initialize(item)
              super(item.width + (2 * INSET), item.height + BACK,
                    item.baseline + BACK)
              @item = item
            end

            def draw(pen, left, top)
              rail = top + baseline
              @item.draw(pen, left + INSET, top + BACK)
              rails(pen, left, rail)
              back(pen, left, rail, top + (BACK / 2))
            end

            private

            def rails(pen, left, rail)
              pen.line(left, rail, left + INSET, rail)
              pen.line(left + INSET + @item.width, rail, left + width, rail)
            end

            def back(pen, left, rail, level)
              near = left + TURN
              far = left + width - TURN
              pen.path(over(near, far, [rail, level]))
              arrow(pen, (near + far) / 2, level)
            end

            def over(near, far, (rail, level))
              [[:move, far, rail], [:line, far, level + TURN],
               Curves.level(far, level + TURN, -TURN, -TURN, TURN),
               [:line, near + TURN, level],
               Curves.upright(near + TURN, level, -TURN, TURN, TURN),
               [:line, near, rail]]
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
