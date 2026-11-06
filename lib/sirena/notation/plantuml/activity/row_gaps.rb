# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Activity
        # The space above each row, as PlantUML leaves it: 20 between
        # steps, 10 from a decision down to a branch beside it, 6 from a
        # branch into the diamond that closes them (23.13 from a join bar,
        # which PlantUML sets off by a step's half-height more), and room
        # for the label
        # of an arrow between two rows. A row is as far from the one above
        # as the largest of its arrows asks. A branch that leaves the foot of
        # its decision rather than its side asks for the label's room.
        class RowGaps
          STEP = 20.0
          BRANCH = 10.0
          CLOSE = 6.0
          BAR_CLOSE = 23.1328
          LABEL_MARGIN = 28.33
          LABEL_BELOW_DECISION = 11.45
          private_constant :STEP, :BRANCH, :CLOSE, :BAR_CLOSE, :LABEL_MARGIN,
                           :LABEL_BELOW_DECISION

          # @param frame [Float] the space a partition's frame asks where an
          #   arrow crosses it
          def initialize(diagram, ranking, exits, metrics, frame)
            @ranking = ranking
            @exits = exits
            @metrics = metrics
            @frame = frame
            @asks = Array.new(ranking.rank.values.max.to_i + 1) { [] }
            diagram.edges.each { |edge| add(edge) }
          end

          # @return [Array<Float>] the space above each row; the first is 0
          def to_a
            @asks.each_with_index.map do |own, row|
              row.zero? ? 0.0 : (own.max || STEP)
            end
          end

          private

          def add(edge)
            return if @ranking.back?(edge)

            row = @ranking.rank[edge.to]
            return unless row - @ranking.rank[edge.from] == 1

            @asks[row] << [crossing(edge), arrow(edge)].max
          end

          def crossing(edge)
            edge.from.partition == edge.to.partition ? 0.0 : @frame
          end

          # Where the arrow goes decides how far it has to run.
          def arrow(edge)
            height = label_height(edge)
            return side_run(edge, height) if beside?(edge)
            return drop(edge, height) if edge.from.kind == :decision

            [STEP, labelled(height)].max
          end

          # A branch that drops from the decision's foot runs straight to its
          # step, or jogs sideways first when its step stands off to one side.
          def drop(edge, height)
            below = height + LABEL_BELOW_DECISION
            return below + LABEL_BELOW_DECISION if @exits.jog?(edge)

            [STEP, below].max
          end

          def side_run(edge, height)
            return close(edge, height) if edge.to.kind == :merge

            edge.from.kind == :decision && !edge.from.bare ? BRANCH : STEP
          end

          def close(edge, height)
            [edge.from.kind == :bar ? BAR_CLOSE : CLOSE, labelled(height)].max
          end

          def beside?(edge)
            @exits.beside?(edge)
          end

          def labelled(height)
            height.zero? ? 0.0 : height + LABEL_MARGIN
          end

          # The text between two rows: the arrow's own label, or a bare
          # decision's question.
          def label_height(edge)
            lines = edge.label.to_s.split("\n")
            lines = edge.to.lines if edge.to.bare && lines.empty?
            lines.empty? ? 0.0 : @metrics.text_height(lines, role: :arrow)
          end
        end
      end
    end
  end
end
