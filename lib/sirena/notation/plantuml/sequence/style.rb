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
        #     groupHeader { FontColor C  BackGroundColor C  FontSize N }
        #   }
        #
        # Anything else makes {.read} return nil, so the parser refuses the
        # block instead of ignoring part of it. The nested forms
        # `group { header { FontColor C  BackGroundColor C } }` and the same
        # under `reference` are read and dropped: PlantUML 1.2026.6 draws
        # them with no effect.
        class Style
          TOKEN = /[{}]|[^\s{}]+/
          PROPERTIES = {
            %w[sequencediagram participant] =>
              { "minimumwidth" => :min_width,
                "horizontalalignment" => :alignment },
            %w[sequencediagram groupheader] =>
              { "fontcolor" => :tab_colour, "backgroundcolor" => :tab_fill,
                "fontsize" => :tab_size },
          }.freeze
          NESTED = {
            "fontcolor" => :ignored, "backgroundcolor" => :ignored
          }.freeze
          INERT = {
            %w[sequencediagram group header] => NESTED,
            %w[sequencediagram reference header] => NESTED,
          }.freeze
          PARENTS = [%w[sequencediagram], %w[sequencediagram group],
                     %w[sequencediagram reference]].freeze
          ALIGNMENTS = %w[left center right].freeze
          NAMED = { "lightyellow" => "#FFFFE0" }.freeze
          private_constant :TOKEN, :PROPERTIES, :NESTED, :INERT, :PARENTS,
                           :ALIGNMENTS, :NAMED

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
            refuse unless known_path?
          end

          def known_path?
            PROPERTIES.key?(@path) || INERT.key?(@path) ||
              PARENTS.include?(@path)
          end

          def assign(name, value)
            key = PROPERTIES.fetch(@path) { INERT.fetch(@path, {}) }
              .fetch(name.downcase) { refuse }
            return if key == :ignored

            @values[key] = convert(key, value.to_s) or refuse
          end

          def convert(key, value)
            return size(value) if %i[min_width tab_size].include?(key)
            return alignment(value) if key == :alignment

            colour(value)
          end

          def size(value)
            number = Integer(value, 10, exception: false)
            number if number&.positive?
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
