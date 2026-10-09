# frozen_string_literal: true

require_relative "scene"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # The frame of an alt/loop/group block: the box, the keyword tab in
        # its top left corner, the guard text and one dashed line per `else`.
        # `block` is the Walker's record of the block.
        class FragmentShape
          TAB_PAD = 8.0
          TAB_HEIGHT = 20.0
          BASE_PAD = 10.0
          NEST_PAD = 8.0

          attr_reader :x, :width

          def initialize(block, bottom, centers, measure)
            @block = block
            @bottom = bottom
            @measure = measure
            low, high = extent(block, centers)
            pad = BASE_PAD + (NEST_PAD * block[:depth])
            @x = low - pad
            @width = [high - low + (2 * pad), minimum_width].max
          end

          def scene
            Scene::Fragment.new(
              x: x, y: @block[:top], width: width,
              height: @bottom - @block[:top], tab_path: tab_path,
              separators: separators, texts: texts
            )
          end

          private

          # A block no item touched spans the whole diagram.
          def extent(block, centers)
            return [centers.first, centers.last] if block[:low] > block[:high]

            [block[:low], block[:high]]
          end

          def group?
            @block[:keyword] == "group"
          end

          def tab_text
            return @block[:keyword] unless group? && !guard.empty?

            guard
          end

          def guard
            @block[:label]
          end

          def bracket(label)
            label.empty? || group? ? nil : "[#{label}]"
          end

          def tab_width
            @measure.call(tab_text) + (2 * TAB_PAD)
          end

          def minimum_width
            guard_width = @measure.call(bracket(guard).to_s)
            tab_width + guard_width + (3 * TAB_PAD)
          end

          def tab_path
            top = @block[:top]
            right = x + tab_width
            "M #{x} #{top} L #{right} #{top} L #{right} #{top + 14} " \
              "L #{right - 6} #{top + TAB_HEIGHT} L #{x} #{top + TAB_HEIGHT} Z"
          end

          def separators
            @block[:branches].map do |y, _label|
              PlantUML::Scene::Segment.new(x1: x, y1: y, x2: x + width, y2: y)
            end
          end

          def texts
            top = @block[:top] + 14
            [text(tab_text, x + TAB_PAD, top, "fragment_tab"),
             *guard_texts(top), *branch_texts]
          end

          def guard_texts(top)
            label = bracket(guard)
            return [] unless label

            [text(label, x + tab_width + TAB_PAD, top, "fragment_guard")]
          end

          def branch_texts
            @block[:branches].filter_map do |y, label|
              next if label.to_s.strip.empty?

              text("[#{label}]", x + TAB_PAD, y + 14, "fragment_guard")
            end
          end

          def text(content, at_x, at_y, role)
            PlantUML::Scene::Text.new(content: content, x: at_x, y: at_y,
                                      role: role, anchor: "start")
          end
        end
      end
    end
  end
end
