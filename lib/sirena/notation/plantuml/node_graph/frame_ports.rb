# frozen_string_literal: true

require_relative "scene"

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # Ports on a container's frame: `portin` along the top edge,
        # `portout` along the bottom, each square straddling the edge, as
        # the PlantUML JAR draws them.
        class FramePorts
          KINDS = %i[portin portout].freeze
          SIDE = 12.0
          GAP = 12.0

          # @return [Boolean] whether `node` sits on the frame of its container
          def self.on_frame?(node)
            !node.parent.nil? && KINDS.include?(node.kind)
          end

          # @param sizes [Hash{Node => Array(Float, Float)}] width, height
          def initialize(sizes)
            @sizes = sizes
          end

          # @return [Float] the frame width the busier side needs
          def width(ports)
            ports.group_by(&:kind).values.map do |side|
              side.sum { |port| @sizes[port][0] + GAP }
            end.max.to_f
          end

          # @param frame [Placed] the container
          # @return [Array<Placed>] the ports, spread along their edge
          def place(frame, ports, depth)
            ports.group_by(&:kind).flat_map do |kind, side|
              side.each_with_index.map do |port, index|
                at = frame.x + (frame.width * (index + 0.5) / side.size)
                put(port, [at, edge(frame, kind)], depth)
              end
            end
          end

          # @return [Placed] the square a link to `box` ends at
          def terminal(box)
            top = box.node.kind == :portin ? box.height - SIDE : 0.0
            Placed.new(node: box.node, x: box.x + ((box.width - SIDE) / 2),
                       y: box.y + top, width: SIDE, height: SIDE,
                       depth: box.depth)
          end

          private

          def edge(frame, kind)
            kind == :portin ? frame.y : frame.y + frame.height
          end

          def put(port, (centre, edge_y), depth)
            width, height = @sizes[port]
            reach = port.kind == :portin ? height - (SIDE / 2) : SIDE / 2
            Placed.new(node: port, x: centre - (width / 2), y: edge_y - reach,
                       width: width, height: height, depth: depth)
          end
        end
      end
    end
  end
end
