# frozen_string_literal: true

require_relative "columns"
require_relative "marks"
require_relative "metrics"
require_relative "placement"
require_relative "ranking"
require_relative "router"
require_relative "scene"

module Sirena
  module Notation
    module PlantUML
      module Activity
        # Places an activity {Diagram} top to bottom: rows from {Ranking},
        # columns from {Columns}, routes from {Router}. The result is
        # deterministic and uses fixed spacing.
        class Layout
          MARGIN = 14.0

          # @param diagram [Diagram]
          # @return [Scene]
          def call(diagram, **)
            ranking = Ranking.new(diagram)
            columns = Columns.new(diagram, ranking)
            marks = build(diagram, ranking, columns, MARGIN)
            if marks.min_x < MARGIN
              marks = build(diagram, ranking, columns,
                            (2 * MARGIN) - marks.min_x)
            end
            marks.scene
          end

          private

          def build(diagram, ranking, columns, margin)
            metrics = Metrics.new(diagram.style)
            placement = Placement.new(diagram, ranking, columns, margin,
                                      metrics)
            router = Router.new(boxes: placement.boxes, ranking: ranking,
                                bottoms: placement.bottoms,
                                gaps: placement.gaps,
                                label_drop: metrics.size(:arrow) + 1)
            Marks.new(diagram, placement, router, metrics).tap(&:build)
          end
        end
      end
    end
  end
end
