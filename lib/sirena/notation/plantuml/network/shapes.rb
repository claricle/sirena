# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Network
        # How a node's `shape` is drawn into a pen.
        module Shapes
          PAPER = "#F1F1F1"
          LID = 8.0
          private_constant :PAPER, :LID

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

          # @return [Float] y of the name's middle: below a cylinder's lid
          def label_middle(shape, box)
            shape == "database" ? box.middle + (LID / 2) : box.middle
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

          # A cylinder: a body whose foot bulges and a full ellipse for the lid.
          def database(pen, box)
            pen.path(body(box), fill: PAPER)
            pen.ellipse(box.centre, box.top + LID, box.width / 2, LID,
                        fill: PAPER)
          end

          def body(box)
            rim = box.top + LID
            foot = box.bottom - LID
            [[:move, box.left, rim], [:line, box.left, foot],
             [:curve, box.centre, foot + (2 * LID), box.right, foot],
             [:line, box.right, rim], [:close]]
          end
        end
      end
    end
  end
end
