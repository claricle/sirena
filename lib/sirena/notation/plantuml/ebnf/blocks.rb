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
          FONT_SIZE = 14
          # The JAR puts a word's baseline 5.2910 below its rail; the pen
          # centres text on `middle`, which sits 0.35 em above the baseline.
          TEXT_DROP = 5.2910 - (0.35 * FONT_SIZE)
          ARROW = 6.0
          ARROW_HALF = 3.0

          # The arrowheads that show a rail's direction. The JAR places one
          # 40% along its rail less two pixels (measured at six spans).
          module Arrow
            module_function

            def forward(pen, from, to, rail)
              start = from + (0.4 * (to - from)) - 2
              pen.polygon(head(start, rail, ARROW), stroke: "none")
            end

            # On the 26-pixel rail out of a rule, which the JAR does not
            # place by the same measure.
            def closing(pen, from, rail)
              pen.polygon(head(from + 11, rail, ARROW), stroke: "none")
            end

            def backward(pen, from, to, rail)
              start = to - (0.4 * (to - from)) - 2
              pen.polygon(head(start, rail, -ARROW), stroke: "none")
            end

            def head(start, rail, length)
              [[start, rail - ARROW_HALF], [start + length, rail],
               [start, rail + ARROW_HALF]]
            end
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
            def initialize(pen, text, style, padding: 10.0)
              super(pen.text_width(text, size: FONT_SIZE) + padding,
                    WORD_HEIGHT, WORD_HEIGHT / 2)
              @text = text
              @style = style
            end

            def draw(pen, left, top)
              pen.rect(left, top, width, height, **@style)
              pen.text(@text, left + (width / 2),
                       top + baseline + TEXT_DROP,
                       anchor: "middle", size: FONT_SIZE)
            end
          end

          # Nothing: just the rail, for the empty branch of an optional.
          class Gap < Block
            def initialize
              super(0.0, GAP, GAP)
            end

            def draw(_pen, _left, _top); end
          end

          # Blocks one after another along the rail.
          class Row < Block
            JOIN = 20.0

            def initialize(items)
              ascent = items.map(&:baseline).max
              descent = items.map { |item| item.height - item.baseline }.max
              super(items.sum(&:width) + (JOIN * (items.size - 1)),
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
                lefts << (lefts.last + item.width + JOIN)
              end
            end

            def join(pen, lefts, rail)
              @items.each_cons(2).with_index do |(item, _), index|
                pen.line(lefts[index] + item.width, rail, lefts[index + 1],
                         rail)
              end
            end
          end

          # Alternatives stacked, the first on the rail, each starting at
          # the stack's left. An empty first branch is a bypass: one rail
          # across the top, with an arrowhead.
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
              bypass(pen, left, rail) if @smooth
              @branches.each_with_index.drop(@smooth ? 1 : 0).each do |one, i|
                level = top + @tops[i] + one.baseline
                draw_branch(pen, one, left, [rail, level])
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

            def bypass(pen, left, rail)
              pen.line(left, rail, left + width, rail)
              Arrow.forward(pen, left, left + width, rail)
            end

            def draw_branch(pen, branch, left, (rail, level))
              inner = left + SIDE
              branch.draw(pen, inner, level - branch.baseline)
              turned = level != rail
              feeds(pen, [[left, inner], [left + width, inner + branch.width]],
                    level, turned)
              turns(pen, left, rail, level) if turned
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
            INSET = 15.0
            TURN = 8.0
            ABOVE = 12.0
            BACK = 5.0

            def initialize(item)
              super(item.width + (2 * INSET), item.height + ABOVE,
                    item.baseline + ABOVE)
              @item = item
            end

            def draw(pen, left, top)
              rail = top + baseline
              @item.draw(pen, left + INSET, top + ABOVE)
              rails(pen, left, rail)
              back(pen, [left + INSET, left + INSET + @item.width],
                   [top + BACK, rail])
            end

            private

            def rails(pen, left, rail)
              pen.line(left, rail, left + INSET, rail)
              pen.line(left + INSET + @item.width, rail, left + width, rail)
            end

            # The loop-back line, the JAR's: a straight run above the item
            # with a bend at each end that drops to the rail.
            def back(pen, (from, to), (level, rail))
              pen.line(from, level, to, level)
              Arrow.backward(pen, from, to, level)
              [[from - INSET + TURN, TURN], [to + INSET - TURN, -TURN]]
                .each { |edge, run| side(pen, edge, run, [level, rail]) }
            end

            def side(pen, edge, run, (level, rail))
              pen.path([[:move, edge, rail - TURN],
                        Curves.level(edge, rail - TURN, run, TURN, TURN)])
              pen.path([[:move, edge, rail - TURN],
                        [:line, edge, level + TURN],
                        Curves.level(edge, level + TURN, run, -TURN, TURN)])
            end
          end
        end
      end
    end
  end
end
