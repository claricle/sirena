# frozen_string_literal: true

module Sirena
  module Layout
    # Positions a graph without a layout engine.
    #
    # elkrb will take this over (see the TODO in Engine#layout_graph). The
    # geometry lives here rather than in the engine so that swap is one
    # call, and so the engine stays about the pipeline.
    #
    # Coordinates follow the ELK convention: a child is positioned inside
    # its parent, not on the page. Only the renderer adds the offsets up.
    class Fallback
      COLUMNS = 3

      # The page edge, and the smallest a grid cell has ever been. Keeping
      # the floor means every diagram that fitted the old fixed grid lands
      # on exactly the coordinates it used to.
      MARGIN = 50
      MIN_CELL_WIDTH = 250
      MIN_CELL_HEIGHT = 200

      # Breathing room around a cell that outgrows the floor, and inside a
      # cluster. Approximate: matching mermaid's spacing is layout parity
      # work, and this is the placeholder it will replace.
      CELL_GAP = 30
      CLUSTER_PADDING = 20

      # @param graph [Hash] the graph to position in place
      # @return [Hash] the same graph
      def self.apply(graph)
        new.apply(graph)
      end

      def apply(graph)
        place(graph[:children]) if graph.is_a?(Hash) && graph[:children]

        graph
      end

      private

      # Clusters pack bottom-up: a box has no size until the things inside
      # it have somewhere to sit, and its column is not wide enough until
      # the box has a size.
      def place(children)
        children.each { |child| pack(child) if cluster?(child) }
        arrange(children)
      end

      def pack(cluster)
        contents = cluster[:children] || []
        contents.each { |child| pack(child) if cluster?(child) }
        arrange(contents)
        fit_cluster(cluster, contents)
      end

      # Only the flowchart transform marks a child as a cluster. Treating
      # every nested child as one resized the boundaries and namespaces
      # that c4, class and er diagrams nest, which is not this change.
      def cluster?(child)
        child.dig(:metadata, :cluster) == true
      end

      # The contents drop below the title band and sit on the padding, then
      # the box takes whatever size that needs — but never less than the
      # title, which would otherwise run out over the edge.
      def fit_cluster(cluster, contents)
        band = title_band(cluster)

        # mermaid draws a box holding only an empty box, and there is
        # nothing inside this one to measure against.
        if contents.empty?
          cluster[:width] = titled_width(cluster)
          cluster[:height] = band + CLUSTER_PADDING
          return
        end

        shift(contents,
              CLUSTER_PADDING - low(contents, :x),
              band - low(contents, :y))

        cluster[:width] = [high(contents, :x, :width) + CLUSTER_PADDING,
                           titled_width(cluster)].max
        cluster[:height] = high(contents, :y, :height) + CLUSTER_PADDING
      end

      # mermaid writes the title inside the box, along the top.
      def title_band(cluster)
        label_size(cluster, :height) + (CLUSTER_PADDING * 2)
      end

      def titled_width(cluster)
        label_size(cluster, :width) + (CLUSTER_PADDING * 2)
      end

      def label_size(cluster, axis)
        label = (cluster[:labels] || []).first
        label ? label[axis].to_i : 0
      end

      # A cell is at least the size it has always been, so ordinary
      # diagrams do not move. A cluster is bigger than that, and widens
      # its own column rather than overlapping the next one.
      def arrange(children)
        rows = children.each_slice(COLUMNS).to_a
        widths = column_widths(rows)
        heights = rows.map { |row| row_height(row) }

        rows.each_with_index do |row, r|
          row.each_with_index do |child, c|
            # A transform that positions its own children keeps them:
            # block and quadrant arrive laid out.
            next if child[:x] && child[:y]

            child[:x] = MARGIN + widths.take(c).sum
            child[:y] = MARGIN + heights.take(r).sum

            # Everything else that nests keeps the order it had: its own
            # children are laid out once it has a place.
            place(child[:children]) if child[:children] && !cluster?(child)
          end
        end
      end

      # Only a cluster may outgrow a cell. Sizing cells to ordinary nodes
      # as well would move every diagram in the project, and that is a
      # different change from this one.
      def column_widths(rows)
        Array.new(COLUMNS) do |col|
          boxes = rows.filter_map { |row| row[col] }.select { |c| cluster?(c) }
          [MIN_CELL_WIDTH, *boxes.map { |c| c[:width].to_i + CELL_GAP }].max
        end
      end

      def row_height(row)
        boxes = row.select { |child| cluster?(child) }
        [MIN_CELL_HEIGHT, *boxes.map { |c| c[:height].to_i + CELL_GAP }].max
      end

      def shift(contents, dx, dy)
        contents.each do |child|
          child[:x] = child[:x].to_i + dx
          child[:y] = child[:y].to_i + dy
        end
      end

      def low(contents, axis)
        contents.map { |child| child[axis].to_i }.min
      end

      def high(contents, axis, size)
        contents.map { |child| child[axis].to_i + child[size].to_i }.max
      end
    end
  end
end
