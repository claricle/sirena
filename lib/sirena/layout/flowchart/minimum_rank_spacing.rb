# frozen_string_literal: true

module Sirena
  module Layout
    class Flowchart < Base
      # Opens an empty rank step for every extra body character in a Mermaid
      # long link. Elkrb places connected boxes on adjacent ranks and does not
      # consume an edge-specific minimum span, so this applies that constraint
      # to its completed downward layout before the graph is turned or
      # mirrored.
      class MinimumRankSpacing
        def self.apply(flat, rank_spacing)
          new(flat, rank_spacing).apply
        end

        def initialize(flat, rank_spacing)
          @flat = flat
          @rank_spacing = rank_spacing
        end

        def apply
          reset_shifts
          long_edges.each { |edge| satisfy(edge) }
          shift_boxes
          @flat
        end

        private

        def reset_shifts
          @tops = @flat[:children].map { |box| box[:y] }.uniq.sort
          @shifts = Array.new(@tops.length, 0.0)
        end

        def shift_boxes
          @flat[:children].each { |box| box[:y] += shift_at(box[:y]) }
        end

        def long_edges
          (@flat[:edges] || []).select do |edge|
            edge.dig(:metadata, :minimum_rank_span).to_i > 1
          end
        end

        def satisfy(edge)
          from, to = endpoint_layers(edge).sort
          missing = edge.dig(:metadata, :minimum_rank_span) - (to - from)
          return unless missing.positive?

          required = missing * @rank_spacing
          additional = required - (@shifts[to] - @shifts[from])
          shift_suffix(to, additional) if additional.positive?
        end

        def endpoint_layers(edge)
          [layer_of(edge[:sources].first), layer_of(edge[:targets].first)]
        end

        def layer_of(box_id)
          box = @flat[:children].find { |child| child[:id] == box_id }
          @tops.index(box[:y])
        end

        def shift_suffix(first, amount)
          (first...@shifts.length).each { |index| @shifts[index] += amount }
        end

        def shift_at(top)
          @shifts.fetch(@tops.index(top))
        end
      end
    end
  end
end
