# frozen_string_literal: true

module Sirena
  module Diagram
    # Mermaid draws a sequence message without its `wrap:`/`nowrap:` prefix,
    # with `<br>` as a line break and with `#9829;`/`#infin;` as the
    # character they name.
    module SequenceText
      WRAP_PREFIX = /\A\s*(?:no)?wrap:\s*/i
      LINE_BREAK = %r{<br\s*/?>}i
      ENTITY = /#(\d+|[A-Za-z][A-Za-z0-9]*);/
      NAMED = {
        "infin" => "∞",
        "hearts" => "♥",
        "amp" => "&",
        "lt" => "<",
        "gt" => ">",
        "quot" => '"',
        "nbsp" => " ",
      }.freeze

      # @param text [String] message text as written in the source
      # @return [String] the text as mermaid draws it
      def self.display(text)
        shown = text.sub(WRAP_PREFIX, "").gsub(LINE_BREAK, " ")
        shown.gsub(ENTITY) do |match|
          name = Regexp.last_match(1)
          next [name.to_i].pack("U") if name.match?(/\A\d+\z/)

          NAMED.fetch(name, match)
        end
      end
    end
  end
end
