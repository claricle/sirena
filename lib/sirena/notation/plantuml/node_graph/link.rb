# frozen_string_literal: true

require_relative "edge"

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # What the arrow of a link says: its line style, colour, thickness
        # and which end carries a head.
        class Link
          LINE_STYLES = %w[dashed dotted].freeze

          attr_reader :color, :color2, :width

          def initialize(arrow)
            @arrow = arrow
            @options = arrow[/\[(.*)\]/, 1].to_s.split(/[,;]/).map(&:strip)
            colours = @options.filter_map { |o| o[/\A#(\w+)\z/, 1] }
            @color, @color2 = colours
            @width = @options.filter_map { |o| o[/\Athickness=(\d+)/, 1] }
              .first.to_i
            @width = 1 if @width < 1
          end

          # @return [Edge] the line this arrow draws from `from` to `to`;
          #   `rest` is the label and the rows it starts and ends at
          def edge(from, to, **rest)
            Edge.new(from: from, to: to, style: style, head: head,
                     color: color, color2: color2, width: width,
                     rank_step: rank_step, backwards: backwards?, **rest)
          end

          def bare
            @arrow.gsub(/\[.*\]/, "")
          end

          def hidden?
            @options.include?("hidden")
          end

          # @return [Symbol] :dashed or :solid
          def style
            dashed = bare.include?(".") || @options.intersect?(LINE_STYLES)
            dashed ? :dashed : :solid
          end

          # @return [Integer] how many ranks on the target sits: a direction
          #   word says it (`down` and `up` one, `left` and `right` none),
          #   otherwise the line is one shorter than it is long, as in the
          #   PlantUML JAR (`->` none, `-->` one, `--->` two)
          def rank_step
            word = bare[/#{References::DIRECTION}/o]
            return word.match?(/up|down/) ? 1 : 0 if word

            [bare.count("-.=") - 1, 0].max
          end

          # @return [Boolean] whether `up` or `left` reads the link from the
          #   target
          def backwards?
            bare.match?(/(?:up|left)(?![[:alpha:]])/)
          end

          # @return [Symbol, nil] :both, :target, :source, :socket or nil
          def head
            ends = [bare.start_with?("<"), bare.end_with?(">")]
            return :both if ends.all?
            return :target if ends.last
            return :source if ends.first

            bare.match?(/0\)|\(0|\)/) ? :socket : nil
          end
        end
      end
    end
  end
end
