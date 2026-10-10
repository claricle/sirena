# frozen_string_literal: true

require_relative "arrow_style"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # Reads the arrow between two participant names: `->`, `<<--`, `o->x`,
        # `-\\`, `<->`. Returns nil for a token outside the forms checked
        # against PlantUML, so the parser refuses the line by name.
        module ArrowSyntax
          extend self

          # The arrow as a part of a longer pattern. A leading or trailing
          # o/x is a decoration only when blanks, or a `[` or `]` or `?` edge,
          # separate it from the names.
          SOURCE = '(?:(?<=[ \t\[])[oxOX])?(?:<<|<|//|/|\\\\\\\\|\\\\)?-(?i:\[hidden\])?-?' \
                   '(?:>>|>|\\\\\\\\|\\\\|//|/)?(?:[oxOX](?=[ \t\]?]|\z))?'
          TOKEN = /\A([oxOX])?(<<|<|\/\/|\/|\\\\|\\)?(--?)
                   (>>|>|\\\\|\\|\/\/|\/)?([oxOX])?\z/x
          HIDDEN = /\[hidden\]/i
          LEFT = { "<<" => :open, "<" => :filled, "//" => :upper_open,
                   "/" => :upper, "\\\\" => :lower_open,
                   "\\" => :lower }.freeze
          RIGHT = { ">>" => :open, ">" => :filled, "\\\\" => :upper_open,
                    "\\" => :upper, "//" => :lower_open,
                    "/" => :lower }.freeze

          # `-[hidden]>` takes its row and its label's room but draws nothing.
          #
          # @return [Array(ArrowStyle, Boolean), nil] the style and whether
          #   the arrow is written pointing at the sender's name
          def read(token)
            hidden = HIDDEN.match?(token)
            match = TOKEN.match(token.sub(HIDDEN, "")) or return
            lead, left, shaft, right, trail = match.captures
            return unless fits?(lead, left, right, trail)

            build(ends(lead, left, LEFT), ends(trail, right, RIGHT),
                  shaft.length == 2, !left.nil? && right.nil?, hidden)
          end

          private

          # Pairs of glyph and decoration for one side; `x` beside a head
          # replaces it, `x` alone and `o` are decorations.
          def ends(mark, glyph, table)
            cross = mark&.downcase == "x"
            kind = cross && glyph ? :cross : table[glyph]
            ArrowEnd.new(glyph: kind || (:cross if cross),
                         circle: mark&.downcase == "o")
          end

          def build(left, right, dashed, reversed, hidden)
            head, tail = reversed ? [left, right] : [right, left]
            [ArrowStyle.new(head: head, tail: tail, dashed: dashed,
                            leftward: reversed, hidden: hidden), reversed]
          end

          # Only the combinations measured against PlantUML.
          def fits?(lead, left, right, trail)
            return false unless left || right

            paired?(left, right) && crossable?(lead, left, "<") &&
              crossable?(trail, right, ">")
          end

          def paired?(left, right)
            !(left && right) || (left == "<" && right == ">")
          end

          # `x` replaces a plain head only.
          def crossable?(mark, glyph, plain)
            mark&.downcase != "x" || glyph.nil? || glyph == plain
          end
        end
      end
    end
  end
end
