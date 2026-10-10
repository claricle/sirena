# frozen_string_literal: true

require_relative "caption"
require_relative "package_color"
require_relative "style_sheet"
require_relative "unsupported_construct_error"

module Sirena
  module Notation
    module PlantUML
      # Reads the lines between `<style>` and `</style>` one at a time.
      #
      # Only `document { <kind> { ... } }` is read, with BackGroundColor on
      # the document and BackGroundColor, FontColor and FontSize on a Caption
      # kind. Any other selector or property raises {UnsupportedConstructError}
      # by name, so a style is never half applied.
      class StyleReader
        DOCUMENT = "document"
        PROPERTIES = { "backgroundcolor" => :background,
                       "fontcolor" => :colour, "fontsize" => :size }.freeze
        OPENING = /\A(\w+)[ \t]*\{\z/
        PROPERTY = /\A(\w+)[ \t]+(\S+)\z/
        CLOSING_TAG = %r{\A</style>\z}i
        private_constant :DOCUMENT, :PROPERTIES, :OPENING, :PROPERTY,
                         :CLOSING_TAG

        def initialize
          @path = []
          @background = nil
          @rules = {}
        end

        # @param text [String] one stripped line inside the block
        # @param number [Integer] its line in the source
        # @return [Symbol] :closed when the line ended the block, else :open
        # @raise [UnsupportedConstructError] on a selector or property not read
        # @raise [Sirena::Parser::ParseError] when the block closes with a
        #   selector still open
        def feed(text, number)
          if CLOSING_TAG.match?(text)
            refuse_open_selector(number)
            return :closed
          end

          read_rule(text, number)
          :open
        end

        # @return [StyleSheet]
        def sheet
          StyleSheet.new(background: @background, rules: @rules.freeze)
        end

        private

        def read_rule(text, number)
          if (match = OPENING.match(text))
            open_selector(match[1], text, number)
          elsif text == "}" && !@path.empty?
            @path.pop
          elsif (match = PROPERTY.match(text))
            set(match[1].downcase, match[2], text, number)
          else
            refuse("style rule form", text, number)
          end
        end

        def refuse_open_selector(number)
          return if @path.empty?

          raise Sirena::Parser::ParseError,
                "Parse error: line #{number} closes the style block " \
                "with #{@path.last} still open"
        end

        def open_selector(name, text, number)
          word = name.downcase
          allowed = @path.empty? ? [DOCUMENT] : caption_kinds_at_document
          unless allowed.include?(word)
            refuse("style selector #{name}", text, number)
          end

          @path << word
        end

        def caption_kinds_at_document
          return [] unless @path == [DOCUMENT]

          Caption::KINDS.map(&:to_s)
        end

        def set(property, value, text, number)
          name = PROPERTIES[property]
          unless settable?(name)
            refuse("style property #{property}", text, number)
          end

          parsed = parse(name, value, text, number)
          return @background = parsed if @path.size == 1

          (@rules[@path.last.to_sym] ||= {})[name] = parsed
        end

        # A document sets only its background; a caption kind sets any.
        def settable?(name)
          scope = @path.size
          name && (scope == 2 || (scope == 1 && name == :background))
        end

        def parse(name, value, text, number)
          return font_size(value, text, number) if name == :size

          PackageColor.hex(value) || refuse("style colour", text, number)
        end

        def font_size(value, text, number)
          return value.to_i if value.match?(/\A[1-9]\d{0,2}\z/)

          refuse("style font size", text, number)
        end

        def refuse(construct, text, number)
          raise UnsupportedConstructError.new(construct: construct,
                                              line: number, text: text)
        end
      end
    end
  end
end
