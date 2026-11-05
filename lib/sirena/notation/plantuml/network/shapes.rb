# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Network
        # How a node's `shape` is drawn into a pen.
        module Shapes
          PAPER = "#F1F1F1"
          private_constant :PAPER

          module_function

          # @param pen [Drawing::Pen]
          # @param box [Drawing::Box]
          def draw(pen, shape, box)
            case shape
            when "database" then database(pen, box)
            when "node" then cube(pen, box)
            else pen.rect(box.left, box.top, box.width, box.height,
                          fill: PAPER)
            end
          end

          def cube(pen, box)
            pen.rect(box.left, box.top, box.width, box.height, fill: PAPER)
            pen.path(edges(box))
          end

          def edges(box)
            left = box.left
            top = box.top - 8
            right = box.right
            [[:move, left, box.top], [:line, left + 8, top],
             [:line, right + 8, top], [:line, right + 8, box.bottom - 8],
             [:line, right, box.bottom]]
          end

          def database(pen, box)
            pen.path(cylinder(box), fill: PAPER)
            pen.path([[:move, box.left, box.top + 8],
                      [:curve, box.centre, box.top + 16, box.right,
                       box.top + 8]])
          end

          def cylinder(box)
            left = box.left
            right = box.right
            top = box.top + 8
            bottom = box.bottom - 8
            [[:move, left, top], [:curve, box.centre, top - 12, right, top],
             [:line, right, bottom],
             [:curve, box.centre, bottom + 12, left, bottom], [:close]]
          end
        end
      end
    end
  end
end
