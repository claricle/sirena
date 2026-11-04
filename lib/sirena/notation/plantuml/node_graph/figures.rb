# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # The outlines of each shape as data. A point is `[fx, fy, dx, dy]`:
        # `fx` of the width plus `dx`, `fy` of the height plus `dy`, from the
        # box's top left. A size reads the same way.
        module Figures
          ORIGIN = [0, 0, 0, 0].freeze
          FULL = [1, 1, 0, 0].freeze
          CORNERS = [[0, 0, 0, 0], [1, 0, 0, 0], [1, 1, 0, 0],
                     [0, 1, 0, 0]].freeze

          BOX = [[:rect, ORIGIN, FULL]].freeze
          FILE = [[:rect, ORIGIN, FULL],
                  [:polygon, [[1, 0, -8, 0], [1, 0, 0, 8], [1, 0, -8, 8]],
                   "#FFFFFF"]].freeze
          COMPONENT = [[:rect, ORIGIN, FULL],
                       [:rect, [0, 0, -6, 8], [0, 0, 12, 6]],
                       [:rect, [0, 0, -6, 18], [0, 0, 12, 6]]].freeze
          NOTE = [[:polygon, [[0, 0, 0, 0], [1, 0, -8, 0], [1, 0, 0, 8],
                              [1, 1, 0, 0], [0, 1, 0, 0]], "#FEFFDD"]].freeze
          ACTOR = [[:circle, [0.5, 0, 0, 8], 8],
                   [:line, [0.5, 0, 0, 16], [0.5, 0, 0, 36]],
                   [:line, [0.5, 0, -12, 22], [0.5, 0, 12, 22]],
                   [:line, [0.5, 0, 0, 36], [0.5, 0, -12, 50]],
                   [:line, [0.5, 0, 0, 36], [0.5, 0, 12, 50]]].freeze
          PORT = [[:rect, [0.5, 0, -6, 0], [0, 0, 12, 12]]].freeze
          DATABASE = [[:path, [[:M, [0, 0, 0, 8]],
                               [:A, [0.5, 0, 0, 8], 1, [1, 0, 0, 8]],
                               [:L, [1, 1, 0, -8]],
                               [:A, [0.5, 0, 0, 8], 1, [0, 1, 0, -8]], [:Z]]],
                      [:path, [[:M, [0, 0, 0, 8]],
                               [:A, [0.5, 0, 0, 8], 0, [1, 0, 0, 8]]], "none"]]
            .freeze
          NODE = [[:polygon, [[0, 0, 0, 8], [0, 0, 8, 0], [1, 0, 0, 0],
                              [1, 0, -8, 8]]],
                  [:polygon, [[1, 0, -8, 8], [1, 0, 0, 0], [1, 1, 0, -8],
                              [1, 1, -8, 0]]],
                  [:rect, [0, 0, 0, 8], [1, 1, -8, -8]]].freeze
          USECASE = [[:ellipse]].freeze
          CLOUD = [[:cloud]].freeze
          INTERFACE = [[:circle, [0.5, 0, 0, 10], 8]].freeze
          CIRCLE = [[:circle, [0.5, 0, 0, 8], 8]].freeze

          BY_KIND = { actor: ACTOR, usecase: USECASE, component: COMPONENT,
                      interface: INTERFACE, portin: PORT, portout: PORT,
                      note: NOTE, database: DATABASE, node: NODE, cloud: CLOUD,
                      file: FILE, circle: CIRCLE }.freeze

          # Where the label goes, by kind: `top` from the box top, else
          # centred; `dy` moves a centred label, `shift` and `shrink` its
          # horizontal middle and width, `left` pins it to the left.
          LABELS = { actor: { top: 52 }, interface: { top: 22 },
                     circle: { top: 20 },
                     portin: { top: 16 }, portout: { top: 16 },
                     note: { top: 4, left: 8 }, database: { dy: 6 },
                     component: { shift: 6, shrink: 6 },
                     node: { dy: 4, shrink: 8 } }.freeze

          module_function

          def for(kind)
            BY_KIND.fetch(kind, BOX)
          end

          def label(kind)
            LABELS.fetch(kind, {})
          end
        end
      end
    end
  end
end
