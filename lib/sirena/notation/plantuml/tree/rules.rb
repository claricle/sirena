# frozen_string_literal: true

require_relative "../style/colour"

module Sirena
  module Notation
    module PlantUML
      module Tree
        # What the `<style>` blocks of a mindmap or work breakdown source say
        # about its nodes and connectors. A rule's selectors nest
        # (`arrow { :depth(2) { LineColor blue } }`); it applies to an
        # element that every selector of its path names: `node`, `arrow`,
        # `boxless`, `:depth(n)`, and the diagram wrapper. A later rule wins
        # over an earlier one of the same specificity, a longer path over a
        # shorter one. A selector this class does not know never matches.
        class Rules
          WRAPPERS = %w[wbsdiagram mindmapdiagram document root
                        element].freeze
          KINDS = %w[node arrow boxless].freeze
          DEPTH = /\A:depth\((\d+)\)\z/
          OPENING = /\A(.+?)[ \t]*\{\z/
          PROPERTY = /\A(\w+)[ \t:]+(.+?)[ \t;]*\z/
          NAMES = { "linecolor" => :stroke, "backgroundcolor" => :fill,
                    "fontcolor" => :font_colour,
                    "linethickness" => :stroke_width,
                    "linestyle" => :dasharray,
                    "roundcorner" => :round_corner }.freeze
          Rule = Struct.new(:path, :properties, :order)
          private_constant :WRAPPERS, :KINDS, :DEPTH, :OPENING, :PROPERTY,
                           :NAMES, :Rule

          # @param text [String] the inside of one `<style>` block
          # @return [Rules]
          def self.parse(text)
            new.add(text)
          end

          def initialize
            @rules = []
          end

          # @param text [String] the inside of one `<style>` block
          # @return [Rules] self
          def add(text)
            path = []
            tokens(text).each { |line| path = read(line, path) }
            self
          end

          # @return [Boolean] whether any rule is set
          def any?
            !@rules.empty?
          end

          # @param depth [Integer] 0 for the root
          # @param boxless [Boolean] whether the node draws no box
          # @return [Hash] the properties the node's rules set
          def node(depth, boxless: false)
            tags = ["node", "depth(#{depth})"]
            tags << "boxless" if boxless
            resolve(tags)
          end

          # @param depth [Integer] the depth of the parent the connector
          #   leaves, 0 for the root
          # @return [Hash] the properties the connector's rules set
          def arrow(depth)
            resolve(["arrow", "depth(#{depth})"])
          end

          private

          def tokens(text)
            text.gsub(%r{//[^\n]*}, "").gsub("{", "{\n").gsub("}", "\n}\n")
              .lines.map(&:strip).reject(&:empty?)
          end

          def read(line, path)
            return path.first(path.length - 1) if line == "}"

            opening = OPENING.match(line)
            return path + [opening[1].downcase.split(/[ \t]*,[ \t]*/)] if
              opening

            store(path, line)
            path
          end

          def store(path, line)
            match = PROPERTY.match(line)
            name = NAMES[match && match[1].downcase]
            return unless name

            @rules << Rule.new(path.dup, { name => match[2] },
                               @rules.length)
          end

          def resolve(tags)
            matching = @rules.select { |rule| applies?(rule.path, tags) }
            ordered = matching.sort_by do |rule|
              [specificity(rule), rule.order]
            end
            typed(ordered.map(&:properties).reduce({}, :merge))
          end

          def applies?(path, tags)
            path.all? do |alternatives|
              alternatives.any? { |selector| names?(selector, tags) }
            end
          end

          def names?(selector, tags)
            return true if WRAPPERS.include?(selector)

            depth = DEPTH.match(selector)
            return tags.include?("depth(#{depth[1]})") if depth

            KINDS.include?(selector) && tags.include?(selector)
          end

          def specificity(rule)
            rule.path.count { |alternatives| !wrapper?(alternatives) }
          end

          def wrapper?(alternatives)
            alternatives.all? { |selector| WRAPPERS.include?(selector) }
          end

          def typed(found)
            found.to_h { |name, value| [name, convert(name, value)] }
              .compact
          end

          def convert(name, value)
            case name
            when :stroke, :fill, :font_colour then Style::Colour.resolve(value)
            when :stroke_width, :round_corner then number(value)
            else dash(value)
            end
          end

          def number(value)
            Float(value)
          rescue ArgumentError
            nil
          end

          def dash(value)
            length = number(value)
            "#{length.to_i},#{length.to_i}" if length&.positive?
          end
        end
      end
    end
  end
end
