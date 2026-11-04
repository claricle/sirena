# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # What the arrow of a link says: its line style, colour, thickness
        # and which end carries a head.
        class Link
          LINE_STYLES = %w[dashed dotted].freeze

          attr_reader :color, :width

          def initialize(arrow)
            @arrow = arrow
            @options = arrow[/\[(.*)\]/, 1].to_s.split(/[,;]/).map(&:strip)
            @color = @options.filter_map { |o| o[/\A#(\w+)\z/, 1] }.first
            @width = @options.filter_map { |o| o[/\Athickness=(\d+)/, 1] }
              .first.to_i
            @width = 1 if @width < 1
          end

          def hidden?
            @options.include?("hidden")
          end

          # @return [Symbol] :dashed or :solid
          def style
            bare = @arrow.gsub(/\[.*\]/, "")
            dashed = bare.include?(".") || @options.intersect?(LINE_STYLES)
            dashed ? :dashed : :solid
          end

          # @return [Symbol, nil] :both, :target, :source, :socket or nil
          def head
            bare = @arrow.gsub(/\[.*\]/, "")
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
