# frozen_string_literal: true

module Sirena
  module Parser
    module Builders
      # Splits the text after `box` into colour and title the way mermaid
      # does: a leading `rgb(...)`-style function or a CSS colour name is
      # the colour; anything else (a hex code included) leaves the whole
      # text as the title.
      module SequenceBoxTitle
        COLOR_FUNCTION = /\A((?:rgba?|hsla?)\s*\([^)]*\))\s*(.*)\z/m
        COLOR_WORD = /\A(\w+)\s*(.*)\z/m
        COLOR_NAMES = %w[
          aliceblue antiquewhite aqua aquamarine azure beige bisque black
          blanchedalmond blue blueviolet brown burlywood cadetblue chartreuse
          chocolate coral cornflowerblue cornsilk crimson cyan darkblue
          darkcyan darkgoldenrod darkgray darkgreen darkgrey darkkhaki
          darkmagenta darkolivegreen darkorange darkorchid darkred darksalmon
          darkseagreen darkslateblue darkslategray darkslategrey darkturquoise
          darkviolet deeppink deepskyblue dimgray dimgrey dodgerblue
          firebrick floralwhite forestgreen fuchsia gainsboro ghostwhite gold
          goldenrod gray green greenyellow grey honeydew hotpink indianred
          indigo ivory khaki lavender lavenderblush lawngreen lemonchiffon
          lightblue lightcoral lightcyan lightgoldenrodyellow lightgray
          lightgreen lightgrey lightpink lightsalmon lightseagreen
          lightskyblue lightslategray lightslategrey lightsteelblue
          lightyellow lime limegreen linen magenta maroon mediumaquamarine
          mediumblue mediumorchid mediumpurple mediumseagreen mediumslateblue
          mediumspringgreen mediumturquoise mediumvioletred midnightblue
          mintcream mistyrose moccasin navajowhite navy oldlace olive
          olivedrab orange orangered orchid palegoldenrod palegreen
          paleturquoise palevioletred papayawhip peachpuff peru pink plum
          powderblue purple rebeccapurple red rosybrown royalblue saddlebrown
          salmon sandybrown seagreen seashell sienna silver skyblue slateblue
          slategray slategrey snow springgreen steelblue tan teal thistle
          tomato transparent turquoise violet wheat white whitesmoke yellow
          yellowgreen
        ].freeze

        # @param text [String] the text after `box`
        # @return [Hash] `color:` (nil when absent) and `title:`
        def self.split(text)
          match = COLOR_FUNCTION.match(text) || named_color(text)
          return { color: nil, title: text } unless match

          { color: match[1], title: match[2].strip }
        end

        def self.named_color(text)
          match = COLOR_WORD.match(text)
          match if match && COLOR_NAMES.include?(match[1].downcase)
        end
        private_class_method :named_color
      end
    end
  end
end
