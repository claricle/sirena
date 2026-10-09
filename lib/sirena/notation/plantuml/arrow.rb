# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # Reads a relation glyph such as `<|--`, `o-down-`, `*.r.>` or `..>`.
      #
      # A glyph is an optional marker, a body of dashes or dots (a dot makes
      # the line dashed) that may carry a direction word between two runs,
      # and an optional marker. Direction words only steer PlantUML's own
      # layout, so they are accepted and dropped.
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
        private_constant :LEFT_MARKER, :RIGHT_MARKER, :RIGHT_IN_LINE, :BODY,
                         :GLYPH, :PLAIN, :KINDS, :PLAIN_HEADS

        # @return [Hash, nil] `:markers` (side to kind, left first), `:dashed`,
        #   `:kind` and `:head` (:left, :right, or :both with a nil kind when
        #   both ends carry a marker) and `:plain` (a bare association
        #   arrow, which a sequence diagram also has); nil for `<->`, which
        #   a sequence diagram also has and which is not drawn here
        def parse(glyph)
          match = GLYPH.match(glyph)
          left, body, right = match.captures
          return if [left, right].all? { |end_| PLAIN_HEADS.include?(end_) }

          dashed = body.include?(".")
          markers = { left: left, right: right }.compact
            .transform_values { |marker| kind_of(marker, dashed) }
          { markers: markers, dashed: dashed, head: head_of(markers),
            kind: single_kind(markers, dashed), plain: PLAIN.match?(glyph) }
        end

        private

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
