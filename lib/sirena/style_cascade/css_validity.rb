# frozen_string_literal: true

module Sirena
  module StyleCascade
    # Whether a raw style VALUE is syntactically valid CSS for a given
    # PROPERTY — a small per-property table, not a CSS grammar. Enough to
    # tell a real declaration from `FILL:bogus`, not to validate every
    # legal `rgb()` argument.
    #
    # A property this table has no opinion on is always valid, so a caller
    # never rejects a property it does not model — this is what lets the
    # cascade read (`ResolvedStyles#cascade`) fall through safely on
    # properties outside fill/stroke/stroke-width without special-casing
    # them.
    #
    # This table is consulted ONLY on the bare-entity / browser-cascade
    # read path. The attributed-entity path (`ResolvedStyles#attributed`)
    # never calls into it at all — that mirrors mermaid's own
    # `userNodeOverrides`, which reads its compiled style map directly with
    # no validation, and is what the D2 XSS-verbatim contract relies on.
    module CssValidity
      CSS_HEX_COLOR = /\A#(?:[0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})\z/i
      private_constant :CSS_HEX_COLOR

      CSS_COLOR_FUNCTION = /\A(?:rgb|rgba|hsl|hsla)\(.+\)\z/i
      private_constant :CSS_COLOR_FUNCTION

      CSS_LENGTH = %r{\A\d+(?:\.\d+)?(?:px|em|rem|%|pt|cm|mm|in|pc|ex|ch|vw|vh)?\z}i
      private_constant :CSS_LENGTH

      # The CSS Color Module Level 4 extended keyword set, plus `none` (a
      # valid `fill`/`stroke` paint keyword, not a general colour) and the
      # two keywords that resolve dynamically (`currentcolor`) or to
      # nothing (`transparent`). Not exhaustive of every legal CSS <color>
      # (system colours, `color(...)`, `lab()` and friends are not
      # corpus-observed here) — sufficient to separate a real declaration
      # from `bogus`.
      CSS_COLOR_KEYWORDS = %w[
        aliceblue antiquewhite aqua aquamarine azure beige bisque black
        blanchedalmond blue blueviolet brown burlywood cadetblue
        chartreuse chocolate coral cornflowerblue cornsilk crimson cyan
        currentcolor darkblue darkcyan darkgoldenrod darkgray darkgreen
        darkgrey darkkhaki darkmagenta darkolivegreen darkorange
        darkorchid darkred darksalmon darkseagreen darkslateblue
        darkslategray darkslategrey darkturquoise darkviolet deeppink
        deepskyblue dimgray dimgrey dodgerblue firebrick floralwhite
        forestgreen fuchsia gainsboro ghostwhite gold goldenrod gray
        green greenyellow grey honeydew hotpink indianred indigo ivory
        khaki lavender lavenderblush lawngreen lemonchiffon lightblue
        lightcoral lightcyan lightgoldenrodyellow lightgray lightgreen
        lightgrey lightpink lightsalmon lightseagreen lightskyblue
        lightslategray lightslategrey lightsteelblue lightyellow lime
        limegreen linen magenta maroon mediumaquamarine mediumblue
        mediumorchid mediumpurple mediumseagreen mediumslateblue
        mediumspringgreen mediumturquoise mediumvioletred midnightblue
        mintcream mistyrose moccasin navajowhite navy none oldlace olive
        olivedrab orange orangered orchid palegoldenrod palegreen
        paleturquoise palevioletred papayawhip peachpuff peru pink plum
        powderblue purple rebeccapurple red rosybrown royalblue
        saddlebrown salmon sandybrown seagreen seashell sienna silver
        skyblue slateblue slategray slategrey snow springgreen steelblue
        tan teal thistle tomato transparent turquoise violet wheat white
        whitesmoke yellow yellowgreen
      ].freeze
      private_constant :CSS_COLOR_KEYWORDS

      COLOR_PROPERTIES = %w[fill stroke].freeze

      # @param property [String] lowercase property name
      # @param value [String]
      # @return [Boolean]
      def self.valid?(property, value)
        case property
        when 'fill', 'stroke' then color?(value)
        when 'stroke-width' then length?(value)
        else true
        end
      end

      # @param value [String]
      # @return [Boolean] whether VALUE is a CSS colour (or the `none`
      #   paint keyword) a real browser's cascade would accept, rather
      #   than dropping the declaration
      def self.color?(value)
        downcased = value.downcase
        CSS_COLOR_KEYWORDS.include?(downcased) ||
          CSS_HEX_COLOR.match?(value) ||
          CSS_COLOR_FUNCTION.match?(value)
      end

      # @param value [String]
      # @return [Boolean] whether VALUE is a CSS <length> `stroke-width`
      #   would accept
      def self.length?(value)
        CSS_LENGTH.match?(value)
      end
    end
  end
end
