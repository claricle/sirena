# frozen_string_literal: true

require_relative "../markdown_text"

module Sirena
  module Diagram
    # Mermaid draws a flowchart label without the syntax that wrote it: the
    # quote or markdown-string delimiters around it, a leading `fa:fa-x`
    # icon, HTML tags, and the doubling of a backslash.
    module FlowchartLabelText
      QUOTED = /\A"(.*)"\z/m
      MARKDOWN = /\A`(.*)`\z/m
      ICON = /\bfa[bklrs]?:fa-[\w-]+\s*/
      BREAK = %r{<br\s*/?>}i
      LINE_BREAK = Regexp.union(BREAK, /\n/)
      TAG = %r{</?[a-zA-Z][^>]*>}
      DOUBLED_BACKSLASH = "\\\\"
      ESCAPED_LINE_BREAK = "\\n"

      # @param text [String, nil] label text as written in the source
      # @return [String, nil] the text as mermaid draws it
      def self.display(text)
        return text if text.nil?

        lines(text).join(" ").strip
      end

      # @param text [String, nil] label text as written in the source
      # @return [Array<String>] the lines mermaid draws, one for each `<br>`
      #   or newline; one empty line for no text
      def self.lines(text)
        shown = visible_source(text.to_s)
        markdown = shown[MARKDOWN, 1]
        return markdown_lines(markdown) if markdown

        parts = shown.split(LINE_BREAK, -1)
        lines = parts.map { |line| tidy(line) }
        lines.empty? ? [""] : lines
      end

      def self.visible_source(text)
        shown = text.strip
        quoted = shown.match(QUOTED)
        return shown unless quoted

        quoted[1].gsub(ESCAPED_LINE_BREAK, "\n")
      end

      def self.markdown_lines(text)
        MarkdownText.parse_lines(text.gsub(BREAK, "\n")).map do |runs|
          tidy(runs.map(&:text).join)
        end
      end

      def self.tidy(text)
        shown = text.gsub(ICON, "").gsub(TAG, "")
        shown.gsub(DOUBLED_BACKSLASH, "\\").gsub(/[[:space:]]+/, " ").strip
      end

      private_class_method :visible_source, :markdown_lines, :tidy
    end
  end
end
