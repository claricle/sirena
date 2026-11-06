# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # The tab over the top left of a package, folder or frame, which
        # holds the first line of its name.
        module Tab
          HEIGHT = 20.0
          # A package's and a folder's tab is a line taller than a frame's.
          LEANING_HEIGHT = 22.49
          SLANT = 7.0
          CHAMFER = 10.0
          PAD = 8.0

          module_function

          # @param left [Float] the container's left edge
          # @param top [Float] the container's top edge
          # @param width [Float] the width of the name
          # @param kind [Symbol] a frame's tab has its lower right corner cut;
          #   a package's and a folder's lean out along their right edge
          # @return [String] the points of the tab's outline
          def points(left, top, width, kind = :package)
            right = left + width + (2 * PAD)
            outline = if kind == :frame
                        chamfered(right,
                                  top)
                      else
                        leaning(right, top)
                      end
            [[left, top], [right, top], *outline, [left, top + height(kind)]]
              .map { |point| point.join(",") }.join(" ")
          end

          # @return [Float] how tall the tab of a container of `kind` is
          def height(kind)
            kind == :frame ? HEIGHT : LEANING_HEIGHT
          end

          # @return [Float] how far below the tab's top the name sits
          def baseline(kind)
            kind == :frame ? 14.5 : 15.5
          end

          def leaning(right, top)
            [[right + SLANT, top + LEANING_HEIGHT]]
          end

          def chamfered(right, top)
            [[right, top + HEIGHT - CHAMFER], [right - CHAMFER, top + HEIGHT]]
          end
          private_class_method :leaning, :chamfered
        end
      end
    end
  end
end
