# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module State
        # How far a placed state graph reaches right and down: its boxes,
        # the points of its routes and its transition labels.
        module Extent
          # @param graph [Hash] a placed graph with routed edges
          # @return [Array(Float, Float)] the farthest x and y
          def self.of(graph)
            reach = graph[:children].map { |node| corner(node) }
            reach += graph[:edges].flat_map { |edge| edge_reach(edge) }
            reach.transpose.map(&:max)
          end

          def self.corner(node)
            [node[:x] + node[:width], node[:y] + node[:height]]
          end

          def self.edge_reach(edge)
            reach = edge[:sections].flat_map { |part| points(part) }
            label = edge[:label_at]
            reach << label_corner(edge[:labels].first, label) if label
            reach
          end

          def self.points(part)
            [part[:startPoint], *part[:bendPoints], part[:endPoint]]
              .map { |point| [point[:x], point[:y]] }
          end

          def self.label_corner(label, spot)
            [spot[:x] + (label[:width] / 2.0),
             spot[:y] + (label[:height] / 2.0)]
          end
        end
      end
    end
  end
end
