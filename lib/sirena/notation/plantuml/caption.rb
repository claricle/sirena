# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # One of the five statements PlantUML draws around a diagram: its
      # `kind` is :title, :header, :footer, :caption or :legend and `text`
      # the one plain line written after the word.
      class Caption
        KINDS = %i[title header footer caption legend].freeze

        # A text this notation can draw as written: no creole or HTML markup,
        # no escape sequence, and none of the alignment words PlantUML reads
        # after `legend`, which open a block.
        PLAIN = /\A[[:alnum:]][[:alnum:] .,:;!?()'-]*\z/
        ARROW_START = /\A\S*(?:--|\.\.|->|<-)/
        ALIGNMENT = /\A(?:left|right|center|top|bottom)\z/i
        LINE = /\A(#{KINDS.join('|')})[ \t]+(.+)\z/io
        private_constant :PLAIN, :ARROW_START, :ALIGNMENT, :LINE

        # @param text [String] one stripped source line
        # @return [Caption, nil] nil when the line is not a caption this
        #   notation draws: another statement, a block form, or markup
        def self.read(text)
          match = LINE.match(text)
          return unless match

          body = match[2].strip
          return unless PLAIN.match?(body) && !ARROW_START.match?(body)
          return if match[1].casecmp?("legend") && ALIGNMENT.match?(body)

          new(match[1].downcase.to_sym, body)
        end

        # @return [Boolean] whether one line of a block is plain text
        def self.plain?(text)
          PLAIN.match?(text) && !ARROW_START.match?(text)
        end

        attr_reader :kind, :text

        def initialize(kind, text)
          @kind = kind
          @text = text
          freeze
        end
      end
    end
  end
end
