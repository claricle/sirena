# frozen_string_literal: true

require_relative "scene"

module Sirena
  module Notation
    module PlantUML
      # What PlantUML draws in a class box's header beyond its name: the
      # circled letter (C for a class, A for an abstract class, I for an
      # interface, E for an enum, @ for an annotation) and, in a class
      # with no members, the two rules of its empty compartments. Placed
      # after layout, from the final box geometry, so it never changes a
      # size.
      module ClassHeader
        extend self

        Glyph = Struct.new(:fill, :outline)

        RADIUS = 11.0
        # Offsets from the class name's baseline and from the start of the
        # circle-and-name block, measured against PlantUML 1.2026.6.
        CENTRE_ABOVE_BASELINE = 5.291
        NAME_GAP = 3.0
        # An empty class is 48 high: its field and method compartments end
        # 32 and 40 below the top.
        EMPTY_HEIGHT = 48.0
        EMPTY_RULES = [32.0, 40.0].freeze
        BLOCK_SHIFT = 0.5
        # Outlines are relative to the circle's centre.
        GLYPHS = {
          class: Glyph.new(
            "#ADD1B2",
            %w[M2.4731,6.1431 Q1.8921,6.4419 1.2529,6.5913 Q0.6138,6.7407
               -0.0918,6.7407 Q-2.5986,6.7407 -3.9185,5.0889
               Q-5.2383,3.437 -5.2383,0.3159 Q-5.2383,-2.8135
               -3.9185,-4.4653 Q-2.5986,-6.1172 -0.0918,-6.1172
               Q0.6138,-6.1172 1.2612,-5.9678 Q1.9087,-5.8184
               2.4731,-5.5195 L2.4731,-2.7969 Q1.8423,-3.3779
               1.2488,-3.6477 Q0.6553,-3.9175 0.0244,-3.9175
               Q-1.3203,-3.9175 -2.0051,-2.8508 Q-2.6899,-1.7842
               -2.6899,0.3159 Q-2.6899,2.4077 -2.0051,3.4744
               Q-1.3203,4.541 0.0244,4.541 Q0.6553,4.541 1.2488,4.2712
               Q1.8423,4.0015 2.4731,3.4204 Z].join(" "),
          ),
          abstract: Glyph.new(
            "#A9DCDF",
            %w[M-0.1367,-4.6519 L-1.2905,0.4199 L1.0254,0.4199 Z
               M-1.6309,-6.8931 L1.3657,-6.8931 L4.7109,5.5 L2.2622,5.5
               L1.4985,2.437 L-1.7803,2.437 L-2.5273,5.5
               L-4.9761,5.5 Z].join(" "),
          ),
          interface: Glyph.new(
            "#B4A7E5",
            %w[M-3.5723,-3.7349 L-3.5723,-5.8931 L3.8071,-5.8931
               L3.8071,-3.7349 L1.3418,-3.7349 L1.3418,4.3418
               L3.8071,4.3418 L3.8071,6.5 L-3.5723,6.5 L-3.5723,4.3418
               L-1.1069,4.3418 L-1.1069,-3.7349 Z].join(" "),
          ),
          enum: Glyph.new(
            "#EB937F",
            %w[M3.6143,6.5 L-4.1055,6.5 L-4.1055,-5.8931 L3.6143,-5.8931
               L3.6143,-3.7349 L-1.6567,-3.7349 L-1.6567,-1.062
               L3.1162,-1.062 L3.1162,1.0962 L-1.6567,1.0962
               L-1.6567,4.3418 L3.6143,4.3418 Z].join(" "),
          ),
          annotation: Glyph.new(
            "#E3664A",
            %w[M2.5767,0.2261 Q2.5767,-0.7119 2.1533,-1.2432
               Q1.73,-1.7744 0.9912,-1.7744 Q0.2524,-1.7744
               -0.1667,-1.2432 Q-0.5859,-0.7119 -0.5859,0.2261
               Q-0.5859,1.1724 -0.1667,1.7036 Q0.2524,2.2349
               0.9912,2.2349 Q1.73,2.2349 2.1533,1.7036 Q2.5767,1.1724
               2.5767,0.2261 Z M4.1206,3.6294 L2.4937,3.6294
               L2.4937,2.9487 Q2.1782,3.3887 1.7507,3.592 Q1.3232,3.7954
               0.7256,3.7954 Q-0.6357,3.7954 -1.47,2.8159 Q-2.3042,1.8364
               -2.3042,0.2261 Q-2.3042,-1.376 -1.4741,-2.3513
               Q-0.644,-3.3267 0.7256,-3.3267 Q1.3149,-3.3267
               1.7632,-3.1233 Q2.2114,-2.9199 2.4937,-2.5298
               L2.4937,-2.8701 Q2.4937,-3.999 1.8752,-4.6133
               Q1.2568,-5.2275 0.1113,-5.2275 Q-1.6152,-5.2275
               -2.7068,-3.7085 Q-3.7983,-2.1895 -3.7983,0.2427
               Q-3.7983,2.791 -2.5366,4.2976 Q-1.2749,5.8042
               0.8252,5.8042 Q1.4893,5.8042 2.1118,5.6091 Q2.7344,5.4141
               3.3071,5.0239 L4.0708,6.4849 Q3.3984,6.9414 2.6057,7.1697
               Q1.813,7.3979 0.9082,7.3979 Q-1.9971,7.3979 -3.7236,5.4639
               Q-5.4502,3.5298 -5.4502,0.2427 Q-5.4502,-2.9697
               -3.8979,-4.8997 Q-2.3457,-6.8296 0.2109,-6.8296
               Q2.0205,-6.8296 3.0706,-5.738 Q4.1206,-4.6465
               4.1206,-2.7622 Z].join(" "),
          ),
        }.freeze
        private_constant :GLYPHS, :CENTRE_ABOVE_BASELINE, :NAME_GAP,
                         :BLOCK_SHIFT,
                         :EMPTY_HEIGHT, :EMPTY_RULES

        # @param diagram [Diagram]
        # @param scene [Scene] class boxes already placed
        # @param measure [#call] width of a text given the text
        # @return [Scene] the same scene, its class boxes dressed
        def apply(diagram, scene, measure)
          kinds = spot_kinds(diagram)
          scene.boxes.select { |box| box.kind == "class" }.each do |box|
            place(box, kinds[box.id], measure)
            rule_empty_compartments(box)
          end
          scene
        end

        # @return [Glyph, nil] the colour and outline of a kind's circle
        def glyph(kind)
          GLYPHS[kind]
        end

        # @return [Boolean] whether `hide circle` is in force
        def circles_hidden?(diagram)
          diagram.directives.any? do |line|
            line.match?(/\Ahide[ \t]+circle\z/i)
          end
        end

        private

        # Class name to kind, empty when `hide circle` is in force.
        def spot_kinds(diagram)
          return {} if circles_hidden?(diagram)

          diagram.classes.to_h { |klass| [klass.name, klass.kind] }
        end

        def rule_empty_compartments(box)
          return unless empty?(box)

          EMPTY_RULES.each { |offset| box.separators << rule_at(box, offset) }
        end

        def rule_at(box, offset)
          y = box.y + offset
          Scene::Segment.new(x1: box.x, y1: y, x2: box.x + box.width, y2: y)
        end

        def empty?(box)
          box.separators.empty? &&
            (box.height - EMPTY_HEIGHT).abs < 0.01 &&
            box.texts.all? { |text| text.role == "class_name" }
        end

        # The circle and the name sit side by side, centred on the box.
        def place(box, kind, measure)
          name = sole_name(box)
          return unless name && GLYPHS.key?(kind)

          left = name.x - (block_width(name, measure) / 2) + BLOCK_SHIFT
          box.spot = spot_at(kind, left, name.y)
          start_after_spot(name, left)
        end

        def start_after_spot(name, left)
          name.x = left + (2 * RADIUS) + NAME_GAP
          name.anchor = "start"
        end

        def sole_name(box)
          names = box.texts.select { |text| text.role == "class_name" }
          names.first if names.one?
        end

        def spot_at(kind, left, baseline)
          Scene::Spot.new(kind: kind.to_s, cx: left + RADIUS,
                          cy: baseline - CENTRE_ABOVE_BASELINE)
        end

        def block_width(name, measure)
          (2 * RADIUS) + NAME_GAP + measure.call(name.content)
        end
      end
    end
  end
end
