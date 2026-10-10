# frozen_string_literal: true

require_relative "c4_bounds"
require_relative "c4_boundary_metrics"

module Sirena
  module Layout
    # Positions a C4 graph the way mermaid does, a port of its c4Renderer.
    #
    # Same contract as Grid.apply, except that every x and y written is
    # absolute: a box inside a boundary is placed on the page, not inside
    # its parent. The boundaries are visited depth first, each one placing
    # its own boxes before the boundaries nested in it, and the canvas is
    # what the page edge and the nested extents leave behind.
    class C4Placement
      # screen.availWidth in the headless Chrome mermaid-cli draws with.
      # Read off the reference render of c4/007, where a 552 wide box
      # wraps and a 216 wide one does not.
      AVAILABLE_WIDTH = 800
      MARGIN_X = 50
      MARGIN_Y = 10
      SHAPES_IN_ROW = 4
      BOUNDARIES_IN_ROW = 2

      # @param graph [Hash] the graph to position in place
      # @return [Hash] the same graph, its metadata holding the :canvas
      def self.apply(graph)
        new.apply(graph)
      end

      def apply(graph)
        @shapes_in_row = row_limit(graph, "Shape", SHAPES_IN_ROW)
        @boundaries_in_row = row_limit(graph, "Boundary", BOUNDARIES_IN_ROW)
        screen = start_screen
        place_boundaries(screen, [global_boundary(graph)])
        graph[:metadata] = graph[:metadata].to_h.merge(canvas: canvas)
        graph
      end

      private

      def row_limit(graph, name, default)
        config = graph.dig(:metadata, :layout_config).to_s
        value = config[/#{name}InRow\D*(\d+)/i, 1].to_i
        value >= 1 ? value : default
      end

      def start_screen
        @max_x = MARGIN_X
        @max_y = MARGIN_Y
        bounds_for(AVAILABLE_WIDTH).tap do |screen|
          screen.start_at(MARGIN_X, MARGIN_Y)
        end
      end

      def bounds_for(width_limit)
        C4Bounds.new(width_limit: width_limit, per_row: @shapes_in_row)
      end

      # Mermaid keeps every box that is in no boundary in an implicit one.
      def global_boundary(graph)
        header = C4BoundaryMetrics.new(label: "global", type: "global")
        { children: graph[:children], global: true, header: header.height }
      end

      def place_boundaries(parent, nodes)
        across = [@boundaries_in_row, nodes.length].min
        bounds = bounds_for(parent.width_limit.to_f / across)
        nodes.each_with_index do |node, index|
          start_bounds(parent, bounds, node, index)
          place_contents(bounds, node)
          frame(node, bounds)
          parent.absorb(bounds)
          grow_canvas(parent)
        end
      end

      def start_bounds(parent, bounds, node, index)
        if (index % @boundaries_in_row).zero?
          x_pos = parent.data.startx + MARGIN_X
          y_pos = parent.data.stopy + MARGIN_Y + header_height(node)
        else
          x_pos = beside_x(bounds)
          y_pos = bounds.data.starty
        end
        bounds.start_at(x_pos, y_pos)
      end

      def beside_x(bounds)
        data = bounds.data
        data.stopx == data.startx ? data.startx : data.stopx + MARGIN_X
      end

      def header_height(node)
        node[:header] || node.dig(:metadata, :header)
      end

      def place_contents(bounds, node)
        children = node[:children].to_a
        boxes, boundaries = children.partition { |child| box?(child) }
        boxes.each { |box| bounds.insert(box) }
        bounds.bump_last_margin unless boxes.empty?
        place_boundaries(bounds, boundaries) unless boundaries.empty?
      end

      def box?(node)
        !node.dig(:metadata, :boundary_type)
      end

      def frame(node, bounds)
        return if node[:global]

        data = bounds.data
        node[:x] = data.startx
        node[:y] = data.starty
        node[:width] = data.stopx - data.startx
        node[:height] = data.stopy - data.starty
      end

      def grow_canvas(parent)
        @max_x = [@max_x, parent.data.stopx].max
        @max_y = [@max_y, parent.data.stopy].max
      end

      def canvas
        {
          width: @max_x - MARGIN_X + (2 * MARGIN_X),
          height: @max_y - MARGIN_Y + (2 * MARGIN_Y),
          title_x: ((@max_x - MARGIN_X) / 2.0) - (4 * MARGIN_X),
          title_y: MARGIN_Y * 2,
        }
      end
    end
  end
end
