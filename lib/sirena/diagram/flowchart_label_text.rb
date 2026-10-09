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
      TAG = %r{</?[a-zA-Z][^>]*>}
      DOUBLED_BACKSLASH = "\\\\"

      # @param text [String, nil] label text as written in the source
      # @return [String, nil] the text as mermaid draws it
      def self.display(text)
        return text if text.nil?

        shown = text.strip
        shown = shown[QUOTED, 1] || shown
        shown = shown.gsub(ICON, "").gsub(BREAK, " ").gsub(TAG, "")
        shown.gsub(DOUBLED_BACKSLASH, "\\").gsub(/[[:space:]]+/, " ").strip
      end
    end
  end
end
