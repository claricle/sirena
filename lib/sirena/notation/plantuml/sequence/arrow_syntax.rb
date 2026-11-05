# frozen_string_literal: true

require_relative "arrow_style"
require_relative "fill"

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
          SOURCE =
            '(?:(?<=[ \t\[])[oxOX])?(?:<<|<|//|/|\\\\\\\\|\\\\)?' \
            '-(?:(?i:\[hidden\])|\[\#(?:\h{3}(?:\h{3})?|[a-zA-Z]+)\])?-?' \
            '(?:>>|>|\\\\\\\\|\\\\|//|/)?(?:[oxOX](?=[ \t\]?]|\z))?'
          TOKEN = /\A([oxOX])?(<<|<|\/\/|\/|\\\\|\\)?(--?)
                   (>>|>|\\\\|\\|\/\/|\/)?([oxOX])?\z/x
          HIDDEN = /\[hidden\]/i
          COLOUR = /\[(\#(?:\h{6}|\h{3}|[a-z]+))\]/i
          LEFT = { "<<" => :open, "<" => :filled, "//" => :upper_open,
                   "/" => :upper, "\\\\" => :lower_open,
                   "\\" => :lower }.freeze
          RIGHT = { ">>" => :open, ">" => :filled, "\\\\" => :upper_open,
                    "\\" => :upper, "//" => :lower_open,
                    "/" => :lower }.freeze

          # `-[hidden]>` takes its row and its label's room but draws nothing.
          # `-[#22A722]>` and `-[#red]>` draw the shaft and head in that colour.
          #
          # @return [Array(ArrowStyle, Boolean), nil] the style and whether
          #   the arrow is written pointing at the sender's name
          def read(token)
            match = TOKEN.match(plain(token)) or return

            from_parts(match.captures, token)
          end

          private

          def from_parts(parts, token)
            lead, left, shaft, right, trail = parts
            return unless fits?(lead, left, right, trail) && colour?(token)

            build(ends(lead, left, LEFT), ends(trail, right, RIGHT),
                  shaft.length == 2, !left.nil? && right.nil?, looks(token))
          end

          def plain(token)
            token.sub(HIDDEN, "").sub(COLOUR, "")
          end

          # A colour in the brackets must be one PlantUML is known to draw.
          def colour?(token)
            written = token[COLOUR, 1]
            written.nil? || !Fill.read(written).nil?
          end

          def looks(token)
            { hidden: HIDDEN.match?(token),
              colour: Fill.read(token[COLOUR, 1])&.colour }
          end

          # Pairs of glyph and decoration for one side; `x` beside a head
          # replaces it, `x` alone and `o` are decorations.
          def ends(mark, glyph, table)
            cross = mark&.downcase == "x"
            kind = cross && glyph ? :cross : table[glyph]
            ArrowEnd.new(glyph: kind || (:cross if cross),
                         circle: mark&.downcase == "o")
          end

          def build(left, right, dashed, reversed, looks)
            head, tail = reversed ? [left, right] : [right, left]
            [ArrowStyle.new(head: head, tail: tail, dashed: dashed,
                            leftward: reversed, **looks), reversed]
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
