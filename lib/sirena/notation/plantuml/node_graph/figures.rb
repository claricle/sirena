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

          BOX = [[:rect, ORIGIN, FULL, 2.5]].freeze
          FILE = [[:rect, ORIGIN, FULL],
                  [:polygon, [[1, 0, -8, 0], [1, 0, 0, 8], [1, 0, -8, 8]],
                   "#FFFFFF"]].freeze
          # The box is rounded; its glyph is a small component icon at the top
          # right, a body with two tabs on its left.
          COMPONENT = [[:rect, ORIGIN, FULL, 2.5],
                       [:rect, [1, 0, -20, 5], [0, 0, 15, 10]],
                       [:rect, [1, 0, -22, 7], [0, 0, 4, 2]],
                       [:rect, [1, 0, -22, 11], [0, 0, 4, 2]]].freeze
          NOTE = [[:polygon, [[0, 0, 0, 0], [1, 0, -10, 0], [1, 0, 0, 10],
                              [1, 1, 0, 0], [0, 1, 0, 0]], "#FEFFDD"]].freeze
          ACTOR = [[:circle, [0.5, 0, 0, 8], 8],
                   [:line, [0.5, 0, 0, 16], [0.5, 0, 0, 43]],
                   [:line, [0.5, 0, -13, 24], [0.5, 0, 13, 24]],
                   [:line, [0.5, 0, 0, 43], [0.5, 0, -13, 58]],
                   [:line, [0.5, 0, 0, 43], [0.5, 0, 13, 58]]].freeze
          PORT = [[:rect, [0.5, 0, -6, 0], [0, 0, 12, 12]]].freeze
          PORT_IN = [[:rect, [0.5, 1, -6, -12], [0, 0, 12, 12]]].freeze
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
          # The containers that wear a tab over the top left edge, which
          # holds their name.
          TABBED = %i[package folder frame].freeze
          USECASE = [[:ellipse]].freeze
          CLOUD = [[:cloud]].freeze
          INTERFACE = [[:circle, [0.5, 0, 0, 10], 8]].freeze
          CIRCLE = [[:circle, [0.5, 0, 0, 8], 8]].freeze

          # What a container is drawn as; any other kind is a plain frame.
          CONTAINERS = { node: NODE, database: DATABASE, cloud: CLOUD }.freeze

          BY_KIND = { actor: ACTOR, usecase: USECASE, component: COMPONENT,
                      interface: INTERFACE, portin: PORT_IN, portout: PORT,
                      note: NOTE, database: DATABASE, node: NODE, cloud: CLOUD,
                      file: FILE, circle: CIRCLE }.freeze

          # Where the label goes, by kind: `top` from the box top, else
          # centred; `dy` moves a centred label, `shift` and `shrink` its
          # horizontal middle and width, `left` pins it to the left.
          LABELS = { actor: { top: 59.5 }, interface: { top: 22 },
                     circle: { top: 20 },
                     portin: { top: 0 }, portout: { top: 12 },
                     note: { top: 4, left: 8 }, database: { dy: 6 },
                     component: { dy: 4 },
                     node: { dy: 4, shrink: 8 } }.freeze

          module_function

          def for(kind)
            BY_KIND.fetch(kind, BOX)
          end

          # @return [Array, nil] the outline of a container of `kind`, nil
          #   for a plain rectangle
          def container(kind)
            CONTAINERS[kind]
          end

          def label(kind)
            LABELS.fetch(kind, {})
          end
        end
      end
    end
  end
end
