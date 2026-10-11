# frozen_string_literal: true

module Sirena
  module Diagram
    # Mermaid draws a flowchart label without the syntax that wrote it: the
    # quote marks around it, a leading `fa:fa-x` icon, HTML tags, and the
    # doubling of a backslash.
    module FlowchartLabelText
      QUOTED = /\A"(.*)"\z/m
      ICON = /\bfa[bklrs]?:fa-[\w-]+\s*/
      BREAK = %r{<br\s*/?>}i
      LINE_BREAK = Regexp.union(BREAK, /\n/)
      TAG = %r{</?[a-zA-Z][^>]*>}
      DOUBLED_BACKSLASH = "\\\\"

      # @param text [String, nil] label text as written in the source
      # @return [String, nil] the text as mermaid draws it
      def self.display(text)
        return text if text.nil?

        tidy(unquote(text).gsub(BREAK, " "))
      end

      # @param text [String, nil] label text as written in the source
      # @return [Array<String>] the lines mermaid draws, one for each `<br>`
      #   or newline; one empty line for no text
      def self.lines(text)
        parts = unquote(text.to_s).split(LINE_BREAK, -1)
        lines = parts.map { |line| tidy(line) }
        lines.empty? ? [""] : lines
      end

      def self.unquote(text)
        shown = text.strip
        shown[QUOTED, 1] || shown
      end

      def self.tidy(text)
        shown = text.gsub(ICON, "").gsub(TAG, "")
        shown.gsub(DOUBLED_BACKSLASH, "\\").gsub(/[[:space:]]+/, " ").strip
      end

      private_class_method :unquote, :tidy
    end
  end
end
