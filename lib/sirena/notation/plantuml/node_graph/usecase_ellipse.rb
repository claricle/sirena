# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # The ellipse of a use case, as the PlantUML JAR sizes it: the
        # smallest ellipse of a fixed proportion that holds every line of
        # the label (each a box of its own width, centred), grown by
        # {GROWTH} all round.
        module UsecaseEllipse
          GROWTH = 3.0
          LEAST_PROPORTION = 0.2
          MOST_PROPORTION = 0.8
          TOLERANCE = 1e-9

          module_function

          # @param widths [Array<Float>] the width of each label line
          # @param line_height [Float]
          # @return [Array(Float, Float)] the width and height of the ellipse
          def size(widths, line_height)
            proportion = proportion(widths.max, widths.size * line_height)
            radius = enclosing_radius(corners(widths, line_height, proportion))
            [2 * (radius + GROWTH), 2 * ((proportion * radius) + GROWTH)]
          end

          # The height of the label over its width, kept within bounds.
          def proportion(width, height)
            (height / width).clamp(LEAST_PROPORTION, MOST_PROPORTION)
          end

          # The corners of each line's box, stretched so the ellipse reads
          # as a circle.
          def corners(widths, line_height, proportion)
            widths.each_with_index.flat_map do |width, index|
              [index, index + 1].product([-width / 2, width / 2])
                .map { |row, x| [x, row * line_height / proportion] }
            end
          end

          # The radius of the smallest circle holding every point.
          def enclosing_radius(points)
            circle = nil
            points.each_with_index do |point, index|
              next if circle && holds?(circle, point)

              circle = around(points.first(index), point)
            end
            circle.last
          end

          def around(earlier, point)
            circle = [point, 0.0]
            earlier.each_with_index do |other, index|
              next if holds?(circle, other)

              circle = across(earlier.first(index), point, other)
            end
            circle
          end

          def across(earlier, point, other)
            circle = diameter(point, other)
            earlier.each do |third|
              circle = through(point, other, third) unless holds?(circle, third)
            end
            circle
          end

          def holds?(circle, point)
            center, radius = circle
            distance(point, center) <= radius + TOLERANCE
          end

          def diameter(one, other)
            center = one.zip(other).map { |pair| pair.sum / 2.0 }
            [center, distance(one, center)]
          end

          def distance(one, other)
            Math.hypot(one[0] - other[0], one[1] - other[1])
          end

          # The circle through three points, found about the first.
          def through(one, two, three)
            origin = Complex(*one)
            u = centre_from(Complex(*two) - origin, Complex(*three) - origin)
            [[origin.real + u.real, origin.imag + u.imag], u.abs]
          end

          def centre_from(first, second)
            d = 2.0 * (first.conj * second).imag
            Complex(0, -1) * ((second * first.abs2) - (first * second.abs2)) / d
          end
        end
      end
    end
  end
end
