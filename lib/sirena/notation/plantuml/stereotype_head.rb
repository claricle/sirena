# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # The header of a lone class carrying one `<<stereotype>>`, as
      # PlantUML 1.2026.6 draws it: the circle at the left, the stereotype
      # and the name stacked and centred on each other to its right. Numbers
      # are offsets from the box's top left corner, measured against the
      # PlantUML jar on stereotypes of three widths and names of three.
      module StereotypeHead
        extend self

        STEREOTYPE_BASELINE = 16.6016
        NAME_BASELINE = 32.668
        CIRCLE_X = 15.0
        CIRCLE_Y = 20.3105
        BLOCK_LEFT = 27.0
        STEREOTYPE_SIDE = 28.0
        NAME_SIDE = 32.0
        NAME_LEFT = 29.0
        private_constant :STEREOTYPE_BASELINE, :NAME_BASELINE, :CIRCLE_X,
                         :CIRCLE_Y, :BLOCK_LEFT, :STEREOTYPE_SIDE,
                         :NAME_SIDE, :NAME_LEFT

        # @param klass [Klass]
        # @param circle [Boolean] whether the circle is drawn
        # @return [Boolean] whether the class gets this header
        def applies?(klass, circle:)
          circle && klass.kind == :class && klass.stereotypes.one? &&
            ClassName.lines(klass.name).one?
        end

        # @return [Float] the width the header alone asks of the box
        def width(stereotype_width, name_width)
          [stereotype_width + STEREOTYPE_SIDE, name_width + NAME_SIDE].max
        end

        # @return [Float] x of the centre line the two rows share, from the
        #   box's left edge
        def centre(stereotype_width, name_width)
          left = name_width + 4.0 > stereotype_width ? NAME_LEFT : BLOCK_LEFT
          left + ([stereotype_width, name_width].max / 2.0)
        end

        # @return [Array<Float>] baselines of the stereotype and the name
        def baselines
          [STEREOTYPE_BASELINE, NAME_BASELINE]
        end

        # @return [Array<Float>] the circle's centre
        def circle_centre
          [CIRCLE_X, CIRCLE_Y]
        end
      end
    end
  end
end
