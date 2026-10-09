# frozen_string_literal: true

require "cgi"

module Sirena
  module Diagram
    # Mermaid writes a generic as `List~T~` and draws it as `List<T>`.
    module GenericText
      PAIR = /~([^~]+)~/

      # @param text [String] source text holding `~T~` pairs
      # @return [String] the text with each pair drawn as `<T>`
      def self.display(text)
        shown = text
        shown = shown.gsub(PAIR, '<\1>') while shown.match?(PAIR)
        shown
      end

      # Like {display}, for member text: a leading `~` is the package
      # visibility mark and not the start of a pair, and an HTML entity such
      # as `&lt;` is drawn as the character it names.
      def self.display_member(text)
        text = CGI.unescapeHTML(text)
        return display(text) unless text.start_with?("~")

        "~#{display(text[1..])}"
      end
    end
  end
end
