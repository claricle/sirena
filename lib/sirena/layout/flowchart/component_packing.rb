# frozen_string_literal: true

module Sirena
  module Layout
    class Flowchart < Base
      # Packs disconnected components into columns while keeping every
      # component's ranks straight. elkrb centres a later rank against the
      # whole page, which puts a disconnected chain on a diagonal when a
      # wide cluster shares its first rank. Dagre instead gives each
      # component a column and packs later components to the left.
      class ComponentPacking
        def self.apply(flat, cluster_names)
          new(flat, cluster_names).apply
        end

        def initialize(flat, cluster_names)
          @flat = flat
          @boxes = flat[:children] || []
          @by_id = @boxes.to_h { |box| [box[:id], box] }
          @cluster_names = cluster_names
        end

        def apply
          found = components
          return @flat unless eligible?(found)

          centre_ranks
          pack(found.reverse)
          @flat
        end

        private

        def eligible?(found)
          return false unless found.size == 2

          found.one? do |component|
            component.one? && @cluster_names.include?(component.first[:id])
          end
        end

        def components
          unseen = @boxes.map { |box| box[:id] }
          links = adjacency
          unseen.each_with_object([]) do |id, found|
            next unless unseen.include?(id)

            ids = connected(id, links)
            unseen -= ids
            found << ids.filter_map { |key| @by_id[key] }
          end
        end

        def adjacency
          links = Hash.new { |hash, key| hash[key] = [] }
          (@flat[:edges] || []).each { |edge| connect(links, edge) }
          links
        end

        def connect(links, edge)
          from = edge[:sources]&.first
          to = edge[:targets]&.first
          return unless @by_id.key?(from) && @by_id.key?(to)

          links[from] << to
          links[to] << from
        end

        def connected(first, links)
          found = []
          pending = [first]
          until pending.empty?
            id = pending.shift
            next if found.include?(id)

            found << id
            pending.concat(links[id])
          end
          found
        end

        def centre_ranks
          @boxes.group_by { |box| box[:y] }.each_value do |rank|
            tallest = rank.map { |box| box[:height] }.max
            rank.each { |box| box[:y] += (tallest - box[:height]) / 2.0 }
          end
        end

        def pack(found)
          offset = 0.0
          found.each do |component|
            centre_rows(component)
            left, right = extent(component)
            component.each { |box| box[:x] += offset - left }
            offset += right - left + spacing
          end
        end

        def centre_rows(component)
          rows = component.group_by { |box| box[:y] }
          widest = rows.values.map { |row| span(row) }.max
          rows.each_value { |row| centre_row(row, widest) }
          @flat
        end

        def centre_row(row, widest)
          shift = ((widest - span(row)) / 2.0) - extent(row).first
          row.each { |box| box[:x] += shift }
        end

        def span(boxes)
          left, right = extent(boxes)
          right - left
        end

        def extent(boxes)
          left = boxes.map { |box| box[:x] }.min
          right = boxes.map { |box| box[:x] + box[:width] }.max
          [left, right]
        end

        def spacing
          @flat.dig(:layoutOptions, Base::ElkOptions::NODE_NODE_SPACING) ||
            Base::DEFAULT_NODE_SPACING
        end
      end
    end
  end
end
