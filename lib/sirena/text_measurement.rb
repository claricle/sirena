# frozen_string_literal: true

require_relative "text_measurement/arial_advances"

module Sirena
  # Estimates text dimensions for layout, in pure Ruby: no font file is read
  # at runtime. Width is the sum of per-glyph advances of the default theme's
  # stack ("Arial, Helvetica, sans-serif"), from the generated ArialAdvances.
  #
  # BOUNDS: every codepoint in ArialAdvances (exact in Liberation Sans, and in
  # Arial wherever Arial has the glyph; macOS Arial lacks U+0487, U+2010,
  # U+202F, U+20BF and U+21D4); CJK and fullwidth at 1.0 em, the four Arabic
  # ligatures in OUTLIERS, and zero-width marks (all measured in Chrome).
  # ESTIMATES: emoji at 1.5 em, everything else at 1.0 em.
  # DOES NOT BOUND: a font the viewer substitutes for a glyph Arial lacks,
  # other stacks (DejaVu, Verdana run up to 1.19 times wider), bold, italic,
  # shaping beyond OUTLIERS. Callers that need room use
  # Renderer::Base#reserved_text_width. Kerning only narrows real text.
  #
  # @example Basic usage
  #   TextMeasurement.measure("Hello", font_size: 14)
  #   # => { width: 31.892, height: 14.0 }
  #
  # @example With dimension overrides
  #   TextMeasurement.measure("Text", font_size: 12, width: 100, height: 20)
  #   # => { width: 100, height: 20 }
  class TextMeasurement
    # Text height as ratio of font size
    HEIGHT_RATIO = 1.0

    # Per-mille em for a codepoint no rule below knows.
    DEFAULT_ADVANCE = 1000
    EMOJI_ADVANCE = 1500
    MONOSPACE_ADVANCE = 600
    SPACE_ADVANCE = ArialAdvances::TABLE.fetch(0x20)

    # SVG draws one <text> as ONE line: a tab, newline or carriage return is
    # collapsed to a space. A CRLF is counted twice (an over-estimate).
    SVG_WHITESPACE = /[\t\n\r]/

    # Codepoints whose width comes from ligature substitution, so no
    # per-character rule describes them. Chrome measured 1.234, 1.025, 1.221
    # and 6.489 em; these round up.
    OUTLIERS = {
      0xFDFA => 1250, 0xFDFB => 1050, 0xFDFC => 1250, 0xFDFD => 6500
    }.freeze

    ZERO_WIDTH = /[\p{Mn}\p{Me}\p{Cf}\p{Cc}]/
    EMOJI = /\p{Extended_Pictographic}/

    # Measures the approximate dimensions of text.
    #
    # @param text [String] the text to measure, as one line: a caller that
    #   draws several lines measures each line on its own
    # @param font_size [Numeric] the font size in points
    # @param width [Numeric, nil] optional width override
    # @param height [Numeric, nil] optional height override
    # @param monospace [Boolean] measure for a monospace font-family
    # @return [Hash] hash with :width and :height keys
    def self.measure(text, font_size:, width: nil, height: nil,
                     monospace: false)
      {
        width: width || calculate_width(text, font_size, monospace),
        height: height || calculate_height(font_size),
      }
    end

    # @return [Float] the width of the text drawn as one line
    def self.calculate_width(text, font_size, monospace)
      total = normalize(text).each_char.sum { |char| advance(char, monospace) }
      total * font_size / 1000.0
    end

    # @return [Integer] the advance of one character in per-mille em
    def self.advance(char, monospace)
      code = char.ord
      table = ArialAdvances::TABLE[code]
      return table_advance(table, monospace) if table
      return whitespace_advance(monospace) if char.match?(SVG_WHITESPACE)

      OUTLIERS.fetch(code) { fallback_advance(char, monospace) }
    end

    # Monospace keeps a zero advance (combining marks) at zero.
    def self.table_advance(table, monospace)
      monospace && table.positive? ? MONOSPACE_ADVANCE : table
    end

    def self.whitespace_advance(monospace)
      monospace ? MONOSPACE_ADVANCE : SPACE_ADVANCE
    end

    def self.fallback_advance(char, monospace)
      return 0 if char.match?(ZERO_WIDTH)
      return EMOJI_ADVANCE if char.match?(EMOJI)

      monospace ? MONOSPACE_ADVANCE : DEFAULT_ADVANCE
    end

    # Never raises on an undecodable string: a layout must not fail on bytes.
    def self.normalize(text)
      string = text.to_s
      string = to_utf8(string) unless string.encoding == Encoding::UTF_8
      string.scrub
    rescue EncodingError
      string.b.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
    end

    # encode from CESU-8 and the UTF8-DoCoMo/KDDI/SoftBank family can leave a
    # stray continuation byte that still reports valid, so re-tag the bytes.
    def self.to_utf8(string)
      utf8 = string.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
      utf8.b.force_encoding(Encoding::UTF_8)
    end

    # @return [Float] the calculated height
    def self.calculate_height(font_size)
      font_size * HEIGHT_RATIO
    end

    private_class_method :calculate_width, :calculate_height, :advance,
                         :fallback_advance, :table_advance, :whitespace_advance,
                         :normalize, :to_utf8
  end
end
