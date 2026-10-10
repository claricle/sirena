# frozen_string_literal: true

module Sirena
  module Layout
    class Flowchart < Base
      # Opens room between the layers of a laid-out level for edge labels,
      # the way dagre gives a label its own rank: a gap grows by the tallest
      # label on an edge that crosses it. Works on a level laid out downward,
      # so a label's room is its size along the flow, `:height` there.
      class LayerSpacing
        # The line box mmdc gives a label is 1.5 times its text height.
        LINE_HEIGHT = 1.5

        # @param flat [Hash] a level whose boxes elkrb has placed
        # @param label_axis [Symbol] :height, or :width for a turned level
        def self.apply(flat, label_axis: :height)
          new(flat, label_axis).apply
        end

        def initialize(flat, label_axis)
          @flat = flat
          @label_axis = label_axis
        end

        def apply
          @tops = @flat[:children].map { |box| box[:y] }.uniq.sort
          @shifts = shifts
          return @flat if @shifts.all?(&:zero?)

          @flat[:children].each { |box| box[:y] += shift_at(box[:y]) }
          route_points.each { |point| point[:y] += shift_between(point[:y]) }
          @flat
        end

        private

        # How far each layer moves down: the room of every gap above it.
        def shifts
          rooms = gap_rooms
          total = 0.0
          @tops.each_index.map do |index|
            total += rooms[index - 1] if index.positive?
            total
          end
        end

        def gap_rooms
          rooms = Array.new(@tops.length, 0.0)
          (@flat[:edges] || []).each do |edge|
            gap = gap_of(edge)
            next unless gap

            rooms[gap] = [rooms[gap], room_of(edge)].max
          end
          rooms
        end

        # The gap an edge's label sits in: the one after the layer halfway
        # along the edge.
        def gap_of(edge)
          from, to = [layer_of(edge[:sources].first),
                      layer_of(edge[:targets].first)].sort
          return if to.zero? || from == to

          (from + to - 1) / 2
        end

        def layer_of(box_id)
          box = @flat[:children].find { |child| child[:id] == box_id }
          @tops.index(box[:y])
        end

        def room_of(edge)
          size = (edge[:labels] || []).filter_map { |l| l[@label_axis] }.max
          return 0.0 unless size

          @label_axis == :height ? size * LINE_HEIGHT : size
        end

        def shift_at(top)
          @shifts[@tops.index(top)]
        end

        # A point between two layers moves with the layer above it.
        def shift_between(y_pos)
          index = @tops.rindex { |top| top <= y_pos } || 0
          @shifts[index]
        end

        def route_points
          (@flat[:edges] || []).flat_map do |edge|
            (edge[:sections] || []).flat_map do |section|
              [section[:startPoint], *section[:bendPoints],
               section[:endPoint]].compact
            end
          end
        end
      end
    end
  end
end
