# frozen_string_literal: true

module Sirena
  module Diagram
    # Mermaid draws a sequence message without its `wrap:`/`nowrap:` prefix
    # and with `<br>` as a line break. `decode` is its character-reference
    # step, which mermaid applies to every piece of sequence text: actor
    # ids, `as` aliases, messages and notes.
    module SequenceText
      WRAP_PREFIX = /\A\s*(?:no)?wrap:\s*/i
      LINE_BREAK = %r{<br\s*/?>}i
      ENTITY = /#(\w+);/
      REPLACEMENT = "�"
      SCALARS = (1..0x10FFFF)
      SURROGATES = (0xD800..0xDFFF)
      C1_CONTROLS = (0x80..0x9F)
      NAMED = {
        "amp" => "&", "AMP" => "&",
        "lt" => "<", "LT" => "<",
        "gt" => ">", "GT" => ">",
        "quot" => '"', "QUOT" => '"',
        "apos" => "'", "nbsp" => " ",
        "infin" => "∞", "hearts" => "♥",
        "copy" => "©", "reg" => "®", "deg" => "°",
        "trade" => "™", "euro" => "€",
        "mdash" => "—", "ndash" => "–", "hellip" => "…",
        "larr" => "←", "rarr" => "→", "uarr" => "↑", "darr" => "↓",
        "times" => "×", "divide" => "÷", "plusmn" => "±",
        "laquo" => "«", "raquo" => "»", "bull" => "•"
      }.freeze

      # @param text [String] message text as written in the source
      # @return [String] the text as mermaid draws it
      def self.display(text)
        decode(text.sub(WRAP_PREFIX, "").gsub(LINE_BREAK, " "))
      end

      # One pass, like mermaid: `#35;59;` gives `#59;`, never `;`. A
      # numeric reference becomes its character, a known name its
      # character, any other name stays as the literal `&name;` (hex
      # `#x41;` included).
      #
      # @param text [String] text as written in the source
      # @return [String] the text with character references decoded
      def self.decode(text)
        text.gsub(ENTITY) do
          name = Regexp.last_match(1)
          next codepoint(name.to_i) if name.match?(/\A\d+\z/)

          NAMED.fetch(name) { "&#{name};" }
        end
      end

      # HTML numeric rules: NUL, surrogates and out-of-range values are
      # U+FFFD, and 0x80-0x9F read as Windows-1252.
      def self.codepoint(number)
        return REPLACEMENT unless SCALARS.cover?(number)
        return REPLACEMENT if SURROGATES.cover?(number)

        character = [number].pack("U")
        return character unless C1_CONTROLS.cover?(number)

        [number].pack("C").force_encoding(Encoding::Windows_1252)
          .encode(Encoding::UTF_8, undef: :replace, replace: character)
      end
      private_class_method :codepoint
    end
  end
end
