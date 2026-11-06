# frozen_string_literal: true

require_relative "routes"

module Sirena
  module Notation
    module PlantUML
      module State
        # How far right a container must reach to hold the labels of the
        # transitions between its members. Graphviz makes each label a node
        # of the rank between the two states it joins, so the labels of one
        # rank stand side by side and the cluster grows to hold them, which a
        # layout that only sees the states does not.
        class LabelReach
          # The room graphviz keeps between two nodes of a rank.
          GAP = 18.0
          # The room between the last label and the cluster's border.
          MARGIN = 12.5
          private_constant :GAP, :MARGIN

          # @param edges [Array<Hash>] every transition of the graph
          # @param parent [Hash{String=>String}] the container of each state
          def initialize(edges, parent)
            @edges = edges.select { |edge| Array(edge[:labels]).any? }
            @parent = parent
          end

          # @param members [Array<Hash>] the placed states of a container,
          #   positioned relative to it
          # @return [Float] the width the container needs for its labels
          def width(members)
            ranks = by_rank(members)
            return 0.0 if ranks.empty?

            ranks.values.map { |labels| placed(labels).last }
              .map { |label, left| left + label.width }.max + MARGIN
          end

          # Where the labels of a rank shared by two or more transitions
          # stand, so each takes its own slot of the rank between its states.
          #
          # @param members [Array<Hash>] as for {#width}
          # @return [Array<Array(Hash, Hash)>] each such transition and its
          #   label centre and the x its line bends through, relative to the
          #   container
          def slots(members)
            ranks = by_rank(members).values.map { |all| all.select(&:direct) }
            ranks = ranks.select { |labels| labels.size > 1 }
            ranks.flat_map { |labels| centres(labels) }
          end

          private

          Label = Struct.new(:edge, :ideal, :width, :row, :down, :direct)
          private_constant :Label

          # The labels of each rank, in the order their edges were drawn.
          def by_rank(members)
            by_id = members.to_h { |node| [node[:id], node] }
            joined = @edges.filter_map { |edge| joint(edge, by_id) }
            joined.group_by(&:first).transform_values do |rows|
              rows.map(&:last)
            end
          end

          # The rank key and the label of an edge between two members.
          def joint(edge, by_id)
            pair = Routes.level_pair(edge, @parent, by_id.keys)
            return unless pair

            from, to = pair.map { |id| by_id.fetch(id) }
            upper, lower = [from, to].sort_by { |node| node[:y] }
            [upper[:y] + upper[:height], label(edge, from, to, upper, lower)]
          end

          def label(edge, from, to, upper, lower)
            Label.new(edge, middle(from, to) + 1, edge[:labels].first[:width],
                      rank_middle(upper, lower), upper.equal?(from),
                      direct?(edge, from, to))
          end

          # Whether the edge joins the two members themselves, not states
          # inside them.
          def direct?(edge, from, to)
            edge.values_at(:sources, :targets).flatten == [from[:id], to[:id]]
          end

          # The row halfway across the gap between the two states.
          def rank_middle(upper, lower)
            bottom = upper[:y] + upper[:height]
            bottom + ((lower[:y] - bottom) / 2.0)
          end

          def middle(from, to)
            centres = [from, to].map { |node| node[:x] + (node[:width] / 2.0) }
            centres.sum / 2.0
          end

          # The group is centred on where its transitions meant to stand,
          # but never left of the container's own edge.
          def centres(labels)
            row = placed(labels)
            slide = slide_for(row, labels)
            row.map do |label, left|
              [label.edge, { x: left + slide + (label.width / 2.0),
                             y: label.row, via: left + slide }]
            end
          end

          def slide_for(row, labels)
            first = row.first.last
            middle = labels.sum(&:ideal) / labels.size
            [middle - (span(row) / 2.0), 0.0].max - first
          end

          def span(row)
            last, left = row.last
            left + last.width - row.first.last
          end

          # Each label of a rank with its left edge: side by side from the
          # ideal spot, those of edges that run down before those that run
          # up.
          def placed(labels)
            ordered = labels.sort_by.with_index do |label, index|
              [label.ideal, label.down ? 0 : 1, index]
            end
            right = 0.0
            ordered.map do |label|
              left = [label.ideal, right + GAP].max
              right = left + label.width
              [label, left]
            end
          end
        end
      end
    end
  end
end
