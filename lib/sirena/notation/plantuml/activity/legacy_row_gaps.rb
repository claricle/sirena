# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Activity
        # The space above each row in the legacy syntax, where PlantUML
        # ranks every node two half-steps apart. An arrow's label takes the
        # half-step in the middle of the arrow, and so does a node parked
        # there; a gap is as tall as the tallest thing in its half-step.
        class LegacyRowGaps
          # Two half-step separations.
          STEP = 40.5
          private_constant :STEP

          def initialize(diagram, ranking, metrics)
            @ranking = ranking
            @metrics = metrics
            @contents = Array.new(ranking.rank.values.max.to_i + 1) { [0.0] }
            diagram.edges.each { |edge| label(edge) }
            diagram.nodes.each { |node| park(node) }
          end

          # @return [Array<Float>] the space above each row; the first is 0
          def to_a
            @contents.each_with_index.map do |own, row|
              row.zero? ? 0.0 : STEP + own.max
            end
          end

          private

          # An arrow that spans an odd number of rows has its label in a
          # gap; over an even number it falls on a row, which it does not
          # grow.
          def label(edge)
            row = middle_gap(edge)
            @contents[row] << label_height(edge) if row
          end

          # @return [Integer, nil] the row a gap lies above
          def middle_gap(edge)
            return if @ranking.back?(edge)

            from = @ranking.rank[edge.from]
            span = @ranking.rank[edge.to] - from
            from + ((span + 1) / 2) if span.odd?
          end

          def park(node)
            return unless @ranking.parked?(node)

            @contents[@ranking.rank[node] + 1] <<
              @metrics.box_for(node).height
          end

          def label_height(edge)
            lines = edge.label.to_s.split("\n")
            lines.empty? ? 0.0 : @metrics.text_height(lines, role: :arrow)
          end
        end
      end
    end
  end
end
