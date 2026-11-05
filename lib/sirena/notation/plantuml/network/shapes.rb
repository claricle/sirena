# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Network
        # How a node's `shape` is sized and drawn into a pen, as the JAR
        # draws it.
        module Shapes
          PAPER = "#F1F1F1"
          HEIGHT = 34.1328
          # The slant of a cube's side, and the rim a cylinder's lid adds.
          DEPTH = 10.0
          LID = 10.0
          PAD = 10.0
          CYLINDER_EXTRA = 9.0
          # Where the name's baseline sits below the top of its flat face.
          DROP = 21.6
          private_constant :PAPER, :DEPTH, :LID, :PAD, :DROP, :CYLINDER_EXTRA

          module_function

          # @param text [Float] the name's width
          # @return [Array(Float, Float)] the shape's width and height
          def size(shape, text)
            case shape
            when "database" then [text + (2 * PAD), HEIGHT + CYLINDER_EXTRA]
            when "node" then [text + (4 * PAD), HEIGHT + DEPTH]
            else [text + (2 * PAD), HEIGHT]
            end
          end

          # @param pen [Drawing::Pen]
          # @param box [Drawing::Box]
          def draw(pen, shape, box)
            case shape
            when "database" then database(pen, box)
            when "node" then cube(pen, box)
            else pen.rect(box.left, box.top, box.width, box.height,
                          fill: PAPER, stroke_width: "0.5")
            end
          end

          # @return [Float] the baseline of the name
          def baseline(shape, box)
            case shape
            when "database" then box.top + DROP + LID + 4.0
            when "node" then box.top + DEPTH + DROP
            else box.top + DROP
            end
          end

          # @return [Float] the middle of the name's x
          def label_x(shape, box)
            shape == "node" ? box.left + ((box.width - DEPTH) / 2) : box.centre
          end

          def cube(pen, box)
            face = box.right - DEPTH
            level = box.top + DEPTH
            pen.polygon(outline(box, face, level), fill: PAPER,
                                                   stroke_width: "0.5")
            pen.path([[:move, face, level], [:line, box.right, box.top]],
                     stroke_width: "0.5")
            pen.path([[:move, box.left, level], [:line, face, level],
                      [:line, face, box.bottom]], stroke_width: "0.5")
          end

          def outline(box, face, level)
            [[box.left, level], [box.left + DEPTH, box.top],
             [box.right, box.top], [box.right, box.bottom - DEPTH],
             [face, box.bottom], [box.left, box.bottom]]
          end

          # A cylinder: a body whose foot bulges and a lid's front edge.
          def database(pen, box)
            pen.path(body(box), fill: PAPER, stroke_width: "0.5")
            pen.path(lid(box), stroke_width: "0.5")
          end

          def lid(box)
            rim = box.top + LID
            [[:move, box.left, rim],
             [:curve, box.left, rim + LID, box.centre, rim + LID],
             [:curve, box.right, rim + LID, box.right, rim]]
          end

          def body(box)
            rim = box.top + LID
            foot = box.bottom - LID
            cap(box, rim) + [[:line, box.right, foot]] + base(box, foot) +
              [[:close]]
          end

          def cap(box, rim)
            [[:move, box.left, rim],
             [:curve, box.left, box.top, box.centre, box.top],
             [:curve, box.right, box.top, box.right, rim]]
          end

          def base(box, foot)
            [[:curve, box.right, box.bottom, box.centre, box.bottom],
             [:curve, box.left, box.bottom, box.left, foot]]
          end
        end
      end
    end
  end
end
