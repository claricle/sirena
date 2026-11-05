# frozen_string_literal: true

require_relative "look"

module Sirena
  module Notation
    module PlantUML
      module State
        # The outline of a note: a sheet with its top-right corner folded
        # down and, on the side that faces the state it annotates, a tail
        # to that state's border.
        class NoteShape
          # @param note [Layout::StateDiagram::Node] the note
          # @param target [Layout::StateDiagram::Node, nil] the state it
          #   annotates
          def initialize(note, target)
            @left = note.x
            @top = note.y
            @right = note.x + note.width
            @bottom = note.y + note.height
            @target = target
          end

          # @return [String] path data of the sheet and its tail
          def outline
            corners = [[@left, @top], [@left, @bottom], [@right, @bottom],
                       [@right, @top + Look::FOLD],
                       [@right - Look::FOLD, @top]]
            index, tail = tail_at
            corners.insert(index, *tail) if tail
            closed(corners)
          end

          # @return [String] path data of the folded corner
          def fold
            edge = @right - Look::FOLD
            closed([[edge, @top], [edge, @top + Look::FOLD],
                    [@right, @top + Look::FOLD]])
          end

          private

          def closed(points)
            "M #{points.map { |point| point.join(' ') }.join(' L ')} Z"
          end

          def middle
            (@top + @bottom) / 2.0
          end

          # @return [Array(Integer, Array), nil] where in the outline the
          #   tail goes, and its three points
          def tail_at
            return unless @target

            if @target.x >= @right
              [3, tail(@right, @target.x)]
            elsif @target.x + @target.width <= @left
              [1, tail(@left, @target.x + @target.width).reverse]
            end
          end

          # Drawn upward along the right side, downward along the left.
          def tail(side, tip_x)
            tip_y = middle.clamp(@target.y, @target.y + @target.height)
            [[side, middle + Look::TAIL], [tip_x, tip_y],
             [side, middle - Look::TAIL]]
          end
        end
      end
    end
  end
end
