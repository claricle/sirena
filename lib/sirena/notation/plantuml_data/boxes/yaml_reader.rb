# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUMLData
      module Boxes
        # Reads the block-style YAML a diagram holds: nested mappings and
        # sequences of plain or quoted scalars. PlantUML does not demand
        # valid YAML (`monospaced: ""monospaced""` is a line it draws), and
        # a loader would also run Ruby's type table over the text, so the
        # lines are read here, by indentation. A key written twice keeps its
        # first place and its last value, as a Hash does.
        class YamlReader
          Line = Data.define(:indent, :text)
          ENTRY = /\A(?:"([^"]*)"|'([^']*)'|([^\s:#"'-][^:]*?|-[^\s][^:]*?))
                   [ \t]*:(?:[ \t]+(.*))?\z/x
          private_constant :Line, :ENTRY

          # @return [Hash, Array, String, nil] the document
          def call(text)
            @lines = text.lines.filter_map { |raw| line_of(raw) }
            @at = 0
            return if @lines.empty?
            return scalar(@lines.first.text) unless structured?(@lines.first)

            block(@lines.first.indent)
          end

          private

          def line_of(raw)
            text = raw.rstrip
            return if text.strip.empty? || text.strip.start_with?("#", "---")

            Line.new(indent: text[/\A */].size, text: text.strip)
          end

          def structured?(line)
            sequence?(line) || ENTRY.match?(line.text)
          end

          def block(indent)
            sequence?(@lines[@at]) ? sequence(indent) : mapping(indent)
          end

          def sequence?(line)
            line.text == "-" || line.text.start_with?("- ")
          end

          def mapping(indent)
            result = {}
            while (line = @lines[@at]) && line.indent == indent
              match = ENTRY.match(line.text)
              break unless match

              @at += 1
              key = match[1] || match[2] || match[3]
              result[key] = value_after(match[4], indent)
            end
            result
          end

          def sequence(indent)
            items = []
            while (line = item_line(indent))
              @at += 1
              rest = line.text.delete_prefix("-").strip
              items << (rest.empty? ? nested(indent) : scalar(rest))
            end
            items
          end

          def item_line(indent)
            line = @lines[@at]
            line if line && line.indent == indent && sequence?(line)
          end

          def value_after(rest, indent)
            return nested(indent) if rest.nil? || rest.empty?

            scalar(rest)
          end

          def nested(indent)
            following = @lines[@at]
            return "" unless following
            return block(following.indent) if following.indent > indent
            if following.indent == indent && sequence?(following)
              return sequence(indent)
            end

            ""
          end

          def scalar(text)
            quoted = text.match(/\A(["'])(.*)\1\z/)
            return quoted[2] if quoted

            text
          end
        end
      end
    end
  end
end
