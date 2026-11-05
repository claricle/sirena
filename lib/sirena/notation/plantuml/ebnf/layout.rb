# frozen_string_literal: true

require_relative "../drawing"
require_relative "blocks"

module Sirena
  module Notation
    module PlantUML
      module Ebnf
        # Draws each rule as a railroad diagram under its name, one below
        # the other: a start dot, the rule's rail and an end dot.
        class Layout
          include Drawing::Pen

          MARGIN = 15.0
          TITLE = 22.0
          LEAD = 26.0
          BETWEEN = 20.0
          RAIL = "1.5"
          BOX = { fill: "#FFFFFF", stroke_width: "0.5" }.freeze
          PLAIN = BOX
          ROUND = BOX.merge(rx: 8.0).freeze
          DASHED = BOX.merge(stroke_dasharray: "4,3").freeze
          private_constant :MARGIN, :TITLE, :LEAD, :BETWEEN, :RAIL, :BOX,
                           :PLAIN, :ROUND, :DASHED

          # @param rules [Array<Rule>]
          # @return [Drawing::Scene]
          def call(rules, **)
            blocks = rules.map { |rule| build(rule.expression) }
            bottom = stack(rules, blocks)
            width = blocks.map(&:width).max + (2 * LEAD) + 8
            scene(width + (2 * MARGIN), bottom - BETWEEN + MARGIN)
          end

          # Rails are thick, as PlantUML draws them.
          def line(*coordinates, **style)
            super(*coordinates, stroke_width: RAIL, **style)
          end

          def path(commands, **style)
            super(commands, stroke_width: RAIL, **style)
          end

          private

          # @return [Float] where the next rule would start
          def stack(rules, blocks)
            rules.zip(blocks).reduce(MARGIN) do |top, (rule, block)|
              draw_rule(rule, block, top)
              top + TITLE + block.height + BETWEEN
            end
          end

          def draw_rule(rule, block, top)
            text(rule.name, MARGIN, top + 6, size: 14, bold: true)
            draw_rail(block, top + TITLE)
          end

          def draw_rail(block, top)
            rail = top + block.baseline
            left = MARGIN + 4
            circle(left, rail, 4, fill: "#FFFFFF", stroke_width: "2")
            line(left + 4, rail, left + LEAD, rail)
            block.draw(self, left + LEAD, top)
            draw_end(left + LEAD + block.width, rail)
          end

          def draw_end(from, rail)
            line(from, rail, from + LEAD, rail)
            Blocks.heading(self, from + Blocks.heading_at(LEAD), rail)
            circle(from + LEAD + 4, rail, 4, fill: INK)
          end

          def build(node)
            case node
            when Literal then Blocks::Word.new(self, node.text, PLAIN)
            when Reference then Blocks::Word.new(self, node.name, ROUND)
            when Special then Blocks::Word.new(self, node.text, DASHED)
            else compound(node)
            end
          end

          def compound(node)
            case node
            when Sequence then Blocks::Row.new(node.items.map { |n| build(n) })
            when Choice then Blocks::Stack.new(node.branches.map do |n|
              build(n)
            end)
            when Optional then Blocks::Stack.new([Blocks::Gap.new,
                                                  build(node.item)])
            else repeated(node)
            end
          end

          def repeated(node)
            loop_block = Blocks::Loop.new(build(node.item))
            return loop_block if node.least.positive?

            Blocks::Stack.new([Blocks::Gap.new, loop_block])
          end
        end
      end
    end
  end
end
