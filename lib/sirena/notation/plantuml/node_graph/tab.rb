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
          # Space left and right of the name inside the tab, as the JAR sets
          # it: a frame's is wider on the right, where its corner is cut.
          PADS = { frame: [3.0, 7.0] }.freeze
          DEFAULT_PADS = [4.0, 2.0].freeze
          private_constant :PADS, :DEFAULT_PADS

          module_function

          # @param left [Float] the container's left edge
          # @param top [Float] the container's top edge
          # @param width [Float] the width of the name
          # @param kind [Symbol] a frame's tab has its lower right corner cut;
          #   a package's and a folder's lean out along their right edge
          # @return [String] the points of the tab's outline
          def points(left, top, width, kind = :package)
            right = left + pads(kind).sum + width
            outline = if kind == :frame
                        chamfered(right,
                                  top)
                      else
                        leaning(right, top)
                      end
            [[left, top], [right, top], *outline, [left, top + height(kind)]]
              .map { |point| point.join(",") }.join(" ")
          end

          # @return [Float] how far right of the tab's edge the name starts
          def indent(kind) = pads(kind).first

          # @return [Float] how tall the tab of a container of `kind` is
          def height(kind)
            kind == :frame ? HEIGHT : LEANING_HEIGHT
          end

          # @return [Float] how far below the tab's top the name sits
          def baseline(kind)
            kind == :frame ? 14.5 : 15.5
          end

          def pads(kind) = PADS.fetch(kind, DEFAULT_PADS)

          def leaning(right, top)
            [[right + SLANT, top + LEANING_HEIGHT]]
          end

          def chamfered(right, top)
            [[right, top + HEIGHT - CHAMFER], [right - CHAMFER, top + HEIGHT]]
          end
          private_class_method :pads, :leaning, :chamfered
        end
      end
    end
  end
end
