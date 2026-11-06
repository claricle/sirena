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

          MARGIN = 10.0
          TITLE_BASE = 23.5352
          TITLE_SIZE = 14
          # From a rule's name down to its rail, and on to the next name.
          RULE_TOP = 12.9531
          RULE_BOTTOM = 28.5352
          LEAD = 26.0
          # Past the end rail: the end dot's diameter and the margin, plus
          # the start dot's radius the left side starts after.
          RIGHT = 18.0
          FOOT = 25.0
          RAIL = "1.5"
          PLAIN = { stroke_width: "0.5" }.freeze
          ROUND = { fill: "#F1F1F1", rx: 5.0, stroke_width: "1.5" }.freeze
          DASHED = { stroke_width: "1", stroke_dasharray: "5,5" }.freeze
          SPECIAL_PADDING = 18.8594
          private_constant :MARGIN, :TITLE_BASE, :TITLE_SIZE, :RULE_TOP,
                           :RULE_BOTTOM, :RAIL, :LEAD, :RIGHT, :FOOT, :PLAIN,
                           :ROUND, :DASHED, :SPECIAL_PADDING

          # @param rules [Array<Rule>]
          # @return [Drawing::Scene]
          def call(rules, **)
            blocks = rules.map { |rule| build(rule.expression) }
            bottom = stack(rules, blocks)
            width = blocks.map(&:width).max + (2 * LEAD) + MARGIN + RIGHT
            scene(width, bottom + FOOT)
          end

          # PlantUML draws the rails at one and a half pixels.
          def line(*coordinates, **style)
            super(*coordinates, stroke_width: RAIL, **style)
          end

          def path(commands, **style)
            super(commands, stroke_width: RAIL, **style)
          end

          private

          # @return [Float] where the last rule's rail ends
          def stack(rules, blocks)
            names = rules.zip(blocks).reduce(TITLE_BASE) do |name, (rule, one)|
              draw_rule(rule, one, name)
              name + RULE_TOP + one.height + RULE_BOTTOM
            end
            names - RULE_BOTTOM
          end

          def draw_rule(rule, block, name)
            text(rule.name, MARGIN, name - (0.35 * TITLE_SIZE),
                 size: TITLE_SIZE, bold: true)
            draw_rail(block, name + RULE_TOP)
          end

          def draw_rail(block, top)
            rail = top + block.baseline
            left = MARGIN + 4
            circle(left, rail, 4, stroke_width: "2")
            line(left + 4, rail, left + LEAD, rail)
            block.draw(self, left + LEAD, top)
            draw_end(left + LEAD + block.width, rail)
          end

          def draw_end(from, rail)
            line(from, rail, from + LEAD, rail)
            Blocks::Arrow.closing(self, from, rail)
            circle(from + LEAD + 4, rail, 4, fill: INK)
          end

          def build(node)
            case node
            when Literal then Blocks::Word.new(self, node.text, PLAIN)
            when Reference then Blocks::Word.new(self, node.name, ROUND)
            when Special then Blocks::Word.new(self, node.text, DASHED,
                                               padding: SPECIAL_PADDING)
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
