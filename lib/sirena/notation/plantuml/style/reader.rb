# frozen_string_literal: true

require_relative "colour"
require_relative "inline"
require_relative "sheet"

module Sirena
  module Notation
    module PlantUML
      module Style
        # Reads the `skinparam` lines and `<style>` blocks of a source into a
        # {Sheet}. A name or property it does not know is left out, never an
        # error: the family reader still decides what it refuses.
        class Reader
          PROPERTIES = {
            "backgroundcolor" => :background, "bordercolor" => :border,
            "linecolor" => :border, "fontcolor" => :font_colour,
            "fontname" => :font_name, "fontsize" => :font_size,
            "linestyle" => :line_style, "roundcorner" => :round_corner,
            "linethickness" => :line_thickness,
            "borderthickness" => :line_thickness,
            "thickness" => :line_thickness, "color" => :border
          }.freeze
          DEFAULTS = {
            "defaultfontname" => :font_name, "defaultfontsize" => :font_size,
            "defaultfontcolor" => :font_colour
          }.freeze
          SUFFIXES = PROPERTIES.keys.sort_by { |name| -name.size }.freeze
          # A selector that names the whole diagram styles its own element.
          WRAPPERS = { "document" => :document, "root" => :document,
                       "element" => :any, "classdiagram" => :class,
                       "statediagram" => :state,
                       "activitydiagram" => :activity }.freeze
          SKINPARAM = /\Askinparam[ \t]+(\S+?)(?:[ \t]*(\{)|[ \t]+(.+))?\z/i
          SINGLE = /\A(\w+)(?:<<(\w+)>>)?\z/
          STYLE_OPEN = %r{\A<style>\z}i
          STYLE_CLOSE = %r{\A</style>\z}i
          OPENING = /\A([\w.]+(?:[ \t]*,[ \t]*[\w.]+)*)[ \t]*\{\z/
          PROPERTY = /\A(\w+)(?:<<(\w+)>>)?[ \t:]+(.+?)[ \t;]*\z/
          INLINE = /\A([\w.]+)[ \t]*\{[ \t]*(\w+)[ \t:]+(.+?)[ \t;]*\}\z/
          LINE_STYLES = { "dotted" => "1,3", "dashed" => "7,7",
                          "bold" => nil }.freeze
          DECLARATION = /\A(?:abstract[ \t]+class|static[ \t]+class|abstract|
                          class|interface|enum|annotation|state)[ \t]+
                         (?:"[^"]+"[ \t]+as[ \t]+)?([A-Za-z_][\w.]*)
                         (?:<[^<>]+>)?(?:[ \t]*<<([^<>]+)>>)*
                         (?:[ \t]*(\#\S+))?/xi
          private_constant :DECLARATION, :PROPERTIES, :DEFAULTS, :SUFFIXES,
                           :WRAPPERS,
                           :SKINPARAM, :SINGLE, :STYLE_OPEN, :STYLE_CLOSE,
                           :OPENING, :PROPERTY, :INLINE, :LINE_STYLES

          # @param source [String] PlantUML source
          # @return [Sheet]
          def self.read(source)
            new.read(source)
          end

          # @param texts [Array<String>] stripped source lines, in order
          # @return [Array<Boolean>] for each line, whether it belongs to a
          #   `skinparam` or `<style>` rule, which this reader owns
          def self.styling?(texts)
            closing = nil
            texts.map do |text|
              if closing
                closing = nil if closing.match?(text)
                next true
              end

              closing = closer(text)
              !closing.nil? || SKINPARAM.match?(text)
            end
          end

          # @return [Regexp, nil] what ends the block this line opens
          def self.closer(text)
            return STYLE_CLOSE if STYLE_OPEN.match?(text)

            /\A\}\z/ if SKINPARAM.match(text)&.[](2)
          end
          private_class_method :closer

          def initialize
            @skin = {}
            @style = {}
            @block = nil
            @path = nil
            @elements = {}
          end

          # @return [Sheet]
          def read(source)
            lines(source).each { |text| feed(text) }
            Sheet.new(skin: @skin, style: @style, elements: @elements)
          end

          private

          def lines(source)
            text = source.dup.force_encoding(Encoding::UTF_8).scrub
            text.lines.map(&:strip).reject do |l|
              l.empty? || l.start_with?("'")
            end
          end

          def feed(text)
            return style_line(text) if @path
            return skin_block_line(text) if @block
            return @path = [] if STYLE_OPEN.match?(text)

            statement(text)
          end

          def statement(text)
            if (match = SKINPARAM.match(text))
              skinparam(match)
            elsif (match = DECLARATION.match(text))
              declaration(match)
            end
          end

          def declaration(match)
            written = Inline.parse(match[3].to_s)
            written[:stereotype] = match[2].downcase if match[2]
            @elements[match[1]] = written unless written.empty?
          end

          def skinparam(match)
            return @block = block_target(match[1]) if match[2]
            return unless match[3]

            name, stereotype = SINGLE.match(match[1])&.captures
            return unless name

            store(@skin, *split(name.downcase), stereotype, match[3])
          end

          def block_target(written)
            name, stereotype = SINGLE.match(written)&.captures
            [name&.downcase, stereotype]
          end

          def skin_block_line(text)
            return @block = nil if text == "}"

            match = PROPERTY.match(text)
            return unless match

            block_property(*@block, match)
          end

          def block_property(element, stereotype, match)
            property = match[1].downcase
            if property.start_with?("arrow")
              element = "arrow"
              property = property.delete_prefix("arrow")
            end
            store(@skin, element&.to_sym, property, match[2] || stereotype,
                  match[3])
          end

          def split(name)
            return [:any, DEFAULTS[name]] if DEFAULTS.key?(name)

            suffix = SUFFIXES.find { |word| name.end_with?(word) }
            return [nil, nil] unless suffix

            element = name.delete_suffix(suffix)
            [element.empty? ? :any : element.to_sym, suffix]
          end

          def style_line(text)
            return @path = nil if STYLE_CLOSE.match?(text)

            if (match = INLINE.match(text))
              inline_property(match)
            elsif (match = OPENING.match(text))
              @path.push(match[1].downcase)
            elsif text == "}"
              @path.pop
            elsif (match = PROPERTY.match(text))
              style_property(match[1].downcase, match[3])
            end
          end

          def inline_property(match)
            @path.push(match[1].downcase)
            style_property(match[2].downcase, match[3])
            @path.pop
          end

          def style_property(property, value)
            selector = @path.last
            # PlantUML's <style> has no BorderColor; only skinparam does.
            return if selector.nil? || property == "bordercolor"

            element, stereotype = target_of(selector)
            store(@style, element&.to_sym, property, stereotype, value)
          end

          def target_of(selector)
            return [WRAPPERS.fetch(selector, selector), nil] unless
              selector.start_with?(".")

            [nil, selector.delete_prefix(".")]
          end

          def store(rules, element, property, stereotype, value)
            name = PROPERTIES.fetch(property, property)
            return unless name.is_a?(Symbol) && (element || stereotype)

            parsed = parse(name, value)
            return if parsed.nil?

            key = Style.selector(canvas(element, name), stereotype)
            (rules[key] ||= {})[name] = parsed
          end

          # A bare `BackgroundColor` is the canvas, not every element.
          def canvas(element, name)
            element == :any && name == :background ? :document : element
          end

          def parse(name, value)
            case name
            when :background, :border, :font_colour then Colour.resolve(value)
            when :font_size, :round_corner, :line_thickness then number(value)
            when :font_name then value.delete('"')
            when :line_style then LINE_STYLES[value.downcase]
            end
          end

          def number(value)
            Float(value)
          rescue ArgumentError
            nil
          end
        end
      end
    end
  end
end
