# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUMLData
      module Boxes
        # The `#highlight "a" / "b" <<class>>` lines of a JSON or YAML
        # diagram and the `<style>` that colours them.
        class Highlights
          DIRECTIVE = /\A#highlight[ \t]+(.+?)(?:[ \t]+<<(\w+)>>)?\z/i
          STYLE = %r{<style>(.*?)</style>}mi
          RULE = /([.\w]+)[ \t]*\{([^{}]*)\}/
          FIELDS = { "backgroundcolor" => :background, "fontcolor" => :color,
                     "fontstyle" => :style }.freeze
          DEFAULT = { background: "#CCFF02", color: "#000000",
                      style: nil }.freeze
          private_constant :DIRECTIVE, :STYLE, :RULE, :FIELDS, :DEFAULT

          # Splits the highlight lines and style off the data.
          #
          # @param text [String] the lines between `@start` and `@end`
          # @return [Array(Highlights, String)] the highlights and the rest
          def self.extract(text)
            styles = text.scan(STYLE).flatten.join("\n")
            rest = text.gsub(STYLE, "")
            lines, data = rest.lines.partition { |l| DIRECTIVE.match?(l.strip) }
            [new(lines.map(&:strip), styles), data.join]
          end

          def initialize(directives = [], style_text = "")
            @styles = parse_styles(style_text)
            @paths = directives.map { |line| parse_directive(line) }
          end

          # @param path [Array<String>] keys from the root to a row
          # @return [Hash, nil] `:background`, `:color` and `:style`
          def style_for(path)
            found = @paths.find { |keys, _| keys == path }
            found && style_of(found.last)
          end

          private

          def parse_directive(line)
            body, name = DIRECTIVE.match(line).captures
            [body.scan(/"((?:[^"\\]|\\.)*)"/).flatten, name]
          end

          def style_of(name)
            DEFAULT.merge(@styles.fetch(name, @styles.fetch("highlight", {})))
          end

          def parse_styles(text)
            text.scan(RULE).to_h do |selector, body|
              [selector.delete_prefix("."), fields(body)]
            end
          end

          def fields(body)
            body.lines.filter_map do |line|
              name, value = line.strip.split(/[ \t]+/, 2)
              field = FIELDS[name.to_s.downcase]
              [field, value.strip] if field && value
            end.to_h
          end
        end
      end
    end
  end
end
