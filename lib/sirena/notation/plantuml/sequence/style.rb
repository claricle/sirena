# frozen_string_literal: true

require_relative "../package_color"
require_relative "appearance"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # Reads one `<style>` block of a sequence diagram:
        #
        #   sequenceDiagram {
        #     participant { MinimumWidth N  HorizontalAlignment L }
        #     groupHeader { FontColor C  BackGroundColor C }
        #   }
        #
        # Anything else makes {.read} return nil, so the parser refuses the
        # block instead of ignoring part of it. The nested form
        # `group { header { ... } }` is among them: PlantUML 1.2026.6 draws
        # it with no effect, and a later release may not.
        class Style
          TOKEN = /[{}]|[^\s{}]+/
          PROPERTIES = {
            %w[sequencediagram participant] =>
              { "minimumwidth" => :min_width,
                "horizontalalignment" => :alignment },
            %w[sequencediagram groupheader] =>
              { "fontcolor" => :tab_colour, "backgroundcolor" => :tab_fill },
          }.freeze
          ALIGNMENTS = %w[left center right].freeze
          NAMED = { "lightyellow" => "#FFFFE0" }.freeze
          private_constant :TOKEN, :PROPERTIES, :ALIGNMENTS, :NAMED

          # @param text [String] what lies between `<style>` and `</style>`
          # @return [Appearance, nil] nil when the block sets anything else
          def self.read(text)
            new(text.scan(TOKEN)).read
          end

          def initialize(tokens)
            @tokens = tokens
            @path = []
            @values = {}
          end

          def read
            catch(:refused) do
              step until @tokens.empty?
              @path.empty? ? Appearance.new(**@values) : nil
            end
          end

          private

          def step
            token = @tokens.shift
            if token == "}"
              @path.empty? ? refuse : @path.pop
            elsif @tokens.first == "{"
              enter(token)
            else
              assign(token, @tokens.shift)
            end
          end

          def enter(name)
            @tokens.shift
            @path << name.downcase
            return if PROPERTIES.key?(@path) || @path == %w[sequencediagram]

            refuse
          end

          def assign(name, value)
            key = PROPERTIES.fetch(@path, {})[name.downcase] or refuse
            @values[key] = convert(key, value.to_s) or refuse
          end

          def convert(key, value)
            return Integer(value, 10, exception: false) if key == :min_width
            return alignment(value) if key == :alignment

            colour(value)
          end

          def alignment(value)
            value.downcase.to_sym if ALIGNMENTS.include?(value.downcase)
          end

          def colour(value)
            return PackageColor.hex(value) if value.start_with?("#")

            NAMED.fetch(value.downcase) { PackageColor::NAMED[value.downcase] }
          end

          def refuse
            throw :refused, nil
          end
        end
      end
    end
  end
end
