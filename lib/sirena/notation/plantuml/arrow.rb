# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # Reads a relation glyph such as `<|--`, `o-down-`, `*.r.>` or `..>`.
      #
      # A glyph is an optional marker, a body of dashes or dots (a dot makes
      # the line dashed) that may carry a direction word between two runs,
      # and an optional marker. The direction word is kept as `:up`, `:down`,
      # `:left` or `:right` for the layout; a one-character body such as
      # `->` or `.>` lays out like `:right`. The body's length, its dashes
      # and dots, sets how many ranks the relation spans.
      module Arrow
        extend self

        LEFT_MARKER = '(?:<\||<|o|\*|\+)'
        RIGHT_MARKER = '(?:\|>|>|o|\*|\+)'
        # A bare `o` or `*` after the body only ends it before a space or a
        # quote; otherwise it starts the class name (`A --oB`).
        RIGHT_IN_LINE = '(?:\|>|>|(?:o|\*|\+)(?=[ \t"]))'
        BODY = "[-.]+(?:(?:up|down|left|right|u|d|l|r)[-.]+)?"

        # Matches one glyph; embed it, then call {parse} on the match.
        PATTERN = "(#{LEFT_MARKER}?#{BODY}#{RIGHT_IN_LINE}?)".freeze

        GLYPH = /\A(#{LEFT_MARKER})?(#{BODY})(#{RIGHT_MARKER})?\z/o
        PLAIN = /\A(?:-->|<--|->|<-)\z/
        KINDS = { "|" => :extension, "o" => :aggregation,
                  "*" => :composition, "+" => :nesting }.freeze
        PLAIN_HEADS = %w[< >].freeze
        DIRECTIONS = { "u" => :up, "d" => :down, "l" => :left,
                       "r" => :right }.freeze
        private_constant :LEFT_MARKER, :RIGHT_MARKER, :RIGHT_IN_LINE, :BODY,
                         :GLYPH, :PLAIN, :KINDS, :PLAIN_HEADS, :DIRECTIONS

        # @return [Hash, nil] `:markers` (side to kind, left first), `:dashed`,
        #   `:kind` and `:head` (:left, :right, or :both with a nil kind when
        #   both ends carry a marker), `:direction` (nil without a word),
        #   `:length` (the body's dashes and dots) and `:plain` (a bare
        #   association
        #   arrow, which a sequence diagram also has); nil for `<->`, which
        #   a sequence diagram also has and which is not drawn here
        def parse(glyph)
          match = GLYPH.match(glyph)
          left, body, right = match.captures
          return if plain_heads?(left, right)

          details(glyph, left, body, right)
        end

        private

        def plain_heads?(left, right)
          [left, right].all? { |end_| PLAIN_HEADS.include?(end_) }
        end

        def details(glyph, left, body, right)
          dashed = body.include?(".")
          markers = { left: left, right: right }.compact
            .transform_values { |marker| kind_of(marker, dashed) }
          { markers: markers, dashed: dashed, head: head_of(markers),
            kind: single_kind(markers, dashed), plain: PLAIN.match?(glyph),
            direction: direction_of(body), length: body.count("-.") }
        end

        def direction_of(body)
          word = body[/[a-z]+/]
          return DIRECTIONS[word[0]] if word

          :right if body.size == 1
        end

        def single_kind(markers, dashed)
          return line_kind(dashed) if markers.empty?

          markers.values.first if markers.size == 1
        end

        def kind_of(marker, dashed)
          shape = marker.delete("<>")
          return line_kind(dashed) if shape.empty?
          return dashed ? :implementation : :extension if shape == "|"

          KINDS.fetch(shape)
        end

        def line_kind(dashed)
          dashed ? :dependency : :association
        end

        def head_of(markers)
          return :both if markers.size == 2

          markers.keys.first
        end
      end
    end
  end
end
