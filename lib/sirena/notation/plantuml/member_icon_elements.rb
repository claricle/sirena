# frozen_string_literal: true

require_relative "../../svg"

module Sirena
  module Notation
    module PlantUML
      # Draws a {Scene::Icon} as SVG, in the colours PlantUML gives each
      # visibility: a stroke and, for a method's filled icon, a fill.
      module MemberIconElements
        extend self

        # visibility => [stroke, fill]
        COLOURS = { "public" => %w[#038048 #84BE84],
                    "private" => %w[#C82930 #F24D5C],
                    "protected" => %w[#B38D22 #FFFF44],
                    "package" => %w[#1963A0 #4177AF] }.freeze
        MODIFIERS = { "public" => "PUBLIC", "private" => "PRIVATE",
                      "protected" => "PROTECTED",
                      "package" => "PACKAGE_PRIVATE" }.freeze
        HALF = { "circle" => 3.0, "square" => 3.0, "diamond" => 4.0,
                 "triangle" => 4.0 }.freeze
        private_constant :COLOURS, :MODIFIERS, :HALF

        # @param icon [Scene::Icon]
        # @return [Svg::Group] the icon, marked with the visibility and kind
        #   of its member as PlantUML marks it
        def group(icon)
          modifier = "#{MODIFIERS.fetch(icon.visibility)}_" \
                     "#{icon.filled ? 'METHOD' : 'FIELD'}"
          Svg::Group.new(data_visibility_modifier: modifier)
            .tap { |group| group << element(icon) }
        end

        # @param icon [Scene::Icon]
        # @return [Svg::Element]
        def element(icon)
          stroke, fill = COLOURS.fetch(icon.visibility)
          fill = "none" unless icon.filled
          return circle(icon, stroke, fill) if icon.shape == "circle"

          styled(shape_of(icon), stroke, fill)
        end

        private

        def shape_of(icon)
          icon.shape == "square" ? square(icon) : polygon(icon)
        end

        def styled(shape, stroke, fill)
          shape.tap do |element|
            element.fill = fill
            element.stroke = stroke
            element.stroke_width = "1"
          end
        end

        def circle(icon, stroke, fill)
          Svg::Circle.new(cx: icon.cx, cy: icon.cy, r: HALF.fetch("circle"),
                          fill: fill, stroke: stroke, stroke_width: "1")
        end

        def square(icon)
          Svg::Rect.new(x: icon.cx - 3.0, y: icon.cy - 3.0, width: 6.0,
                        height: 6.0)
        end

        def polygon(icon)
          half = HALF.fetch(icon.shape)
          points = if icon.shape == "diamond"
                     diamond_points(icon, half)
                   else
                     triangle_points(icon, half)
                   end
          Svg::Polygon.new(points: Svg::Polygon.build_points(points))
        end

        def triangle_points(icon, half)
          [[icon.cx, icon.cy - 3.0], [icon.cx - half, icon.cy + 3.0],
           [icon.cx + half, icon.cy + 3.0]]
        end

        def diamond_points(icon, half)
          [[icon.cx, icon.cy - half], [icon.cx + half, icon.cy],
           [icon.cx, icon.cy + half], [icon.cx - half, icon.cy]]
        end
      end
    end
  end
end
