# frozen_string_literal: true

require_relative 'base'

module Sirena
  module Renderer
    # C4 renderer for converting graphs to SVG.
    #
    # Converts a laid-out graph structure (with computed positions) into
    # SVG using the Svg builder classes. Handles C4 elements, boundaries,
    # and relationships with proper C4 visual conventions.
    #
    # @example Render a C4 diagram
    #   renderer = C4Renderer.new
    #   svg = renderer.render(laid_out_graph)
    class C4Renderer < Base
      # C4 standard colors (from C4-PlantUML)
      C4_COLORS = {
        person: { bg: '#08427B', border: '#073B6F', text: '#FFFFFF' },
        person_ext: { bg: '#6C6477', border: '#4A4552', text: '#FFFFFF' },
        system: { bg: '#1168BD', border: '#0B4884', text: '#FFFFFF' },
        system_ext: { bg: '#8F8F8F', border: '#6B6B6B', text: '#FFFFFF' },
        container: { bg: '#438DD5', border: '#2E6295', text: '#FFFFFF' },
        component: { bg: '#85BBF0', border: '#5D8FB9', text: '#000000' },
        boundary: { bg: '#FFFFFF', border: '#9BA7B4', text: '#000000' }
      }.freeze

      # Element dimensions
      PERSON_WIDTH = 140
      PERSON_HEIGHT = 180
      PERSON_ICON_SIZE = 48
      SYSTEM_WIDTH = 160
      SYSTEM_HEIGHT = 120
      CONTAINER_WIDTH = 160
      CONTAINER_HEIGHT = 120
      COMPONENT_WIDTH = 160
      COMPONENT_HEIGHT = 100

      # Text spacing
      TEXT_PADDING = 10
      LINE_HEIGHT = 16

      # Arrow size
      ARROW_SIZE = 8

      # Renders a laid-out graph to SVG.
      #
      # @param graph [Hash] laid-out graph with node positions
      # @return [Svg::Document] the rendered SVG document
      def render(graph)
        svg = create_document(graph)

        # Render boundaries first (under elements)
        render_boundaries(graph[:children], svg) if graph[:children]

        # Render relationships (under elements but over boundaries)
        render_relationships(graph[:edges], graph[:children], svg) if
          graph[:edges]

        # Render elements (on top)
        render_elements(graph[:children], svg) if graph[:children]

        svg
      end

      protected

      def calculate_width(graph)
        return 800 unless graph[:children]

        # Find rightmost element
        max_x = 0
        traverse_children(graph[:children]) do |child|
          next unless child[:x] && child[:width]

          right_edge = child[:x] + child[:width]
          max_x = [max_x, right_edge].max
        end

        max_x + 40 # Add padding
      end

      def calculate_height(graph)
        return 600 unless graph[:children]

        # Find bottommost element
        max_y = 0
        traverse_children(graph[:children]) do |child|
          next unless child[:y] && child[:height]

          bottom_edge = child[:y] + child[:height]
          max_y = [max_y, bottom_edge].max
        end

        max_y + 40 # Add padding
      end

      def traverse_children(children, &block)
        children.each do |child|
          block.call(child)
          traverse_children(child[:children], &block) if child[:children]
        end
      end

      def render_boundaries(children, svg)
        children.each do |child|
          next unless child[:metadata] && child[:metadata][:boundary_type]

          render_boundary(child, svg)
        end
      end

      def render_boundary(boundary, svg)
        return unless boundary[:x] && boundary[:y]

        group = Svg::Group.new.tap do |g|
          g.id = "boundary-#{boundary[:id]}"
        end

        # Boundary rectangle with dashed border
        rect = Svg::Rect.new.tap do |r|
          r.x = boundary[:x]
          r.y = boundary[:y]
          r.width = boundary[:width]
          r.height = boundary[:height]
          r.fill = C4_COLORS[:boundary][:bg]
          r.stroke = C4_COLORS[:boundary][:border]
          r.stroke_width = '2'
          r.stroke_dasharray = '10,5'
          r.rx = 8
          r.ry = 8
        end
        group.children << rect

        # Boundary label
        label = boundary[:labels]&.first
        if label
          text = Svg::Text.new.tap do |t|
            t.x = boundary[:x] + TEXT_PADDING
            t.y = boundary[:y] + 20
            t.content = label[:text]
            t.fill = C4_COLORS[:boundary][:text]
            t.font_family = 'Arial, sans-serif'
            t.font_size = '16'
            t.font_weight = 'bold'
          end
          group.children << text
        end

        svg << group

        # Render nested boundaries recursively
        if boundary[:children]
          render_boundaries(boundary[:children], svg)
        end
      end

      def render_elements(children, svg)
        children.each do |child|
          metadata = child[:metadata]
          next unless metadata

          if metadata[:boundary_type]
            # Skip boundaries (already rendered)
            # But render their child elements
            render_elements(child[:children], svg) if child[:children]
          else
            # Render element
            render_element(child, svg)
          end
        end
      end

      def render_element(element, svg)
        return unless element[:x] && element[:y]

        metadata = element[:metadata]
        return unless metadata

        group = Svg::Group.new.tap do |g|
          g.id = "element-#{element[:id]}"
        end

        # Determine element type and render accordingly
        if metadata[:person]
          render_person_element(element, group)
        elsif metadata[:system]
          render_system_element(element, group)
        elsif metadata[:container]
          render_container_element(element, group)
        elsif metadata[:component]
          render_component_element(element, group)
        else
          # Default to system rendering
          render_system_element(element, group)
        end

        svg << group
      end

      def render_person_element(element, group)
        x = element[:x]
        y = element[:y]
        w = element[:width] || PERSON_WIDTH
        h = element[:height] || PERSON_HEIGHT

        # Determine colors based on external flag
        colors = if element[:metadata][:external]
                   C4_COLORS[:person_ext]
                 else
                   C4_COLORS[:person]
                 end

        # Person box with rounded corners
        rect = Svg::Rect.new.tap do |r|
          r.x = x
          r.y = y
          r.width = w
          r.height = h
          r.fill = colors[:bg]
          r.stroke = colors[:border]
          r.stroke_width = '2'
          r.rx = 10
          r.ry = 10
        end
        group.children << rect

        # Person icon (simple circle with smaller circle as head)
        icon_cx = x + w / 2
        icon_y = y + 30

        # Head
        head = Svg::Circle.new.tap do |c|
          c.cx = icon_cx
          c.cy = icon_y
          c.r = 16
          c.fill = colors[:text]
        end
        group.children << head

        # Body (simplified)
        body = Svg::Ellipse.new.tap do |e|
          e.cx = icon_cx
          e.cy = icon_y + 35
          e.rx = 24
          e.ry = 28
          e.fill = colors[:text]
        end
        group.children << body

        # Render labels below icon
        render_element_labels(element, x, y + 95, w, colors[:text], group)
      end

      def render_system_element(element, group)
        x = element[:x]
        y = element[:y]
        w = element[:width] || SYSTEM_WIDTH
        h = element[:height] || SYSTEM_HEIGHT

        # Determine colors based on external flag
        colors = if element[:metadata][:external]
                   C4_COLORS[:system_ext]
                 else
                   C4_COLORS[:system]
                 end

        # System box
        rect = Svg::Rect.new.tap do |r|
          r.x = x
          r.y = y
          r.width = w
          r.height = h
          r.fill = colors[:bg]
          r.stroke = colors[:border]
          r.stroke_width = '2'
          r.rx = 5
          r.ry = 5
        end
        group.children << rect

        # Render labels
        render_element_labels(element, x, y + 20, w, colors[:text], group)
      end

      def render_container_element(element, group)
        x = element[:x]
        y = element[:y]
        w = element[:width] || CONTAINER_WIDTH
        h = element[:height] || CONTAINER_HEIGHT

        colors = C4_COLORS[:container]

        # Container box
        rect = Svg::Rect.new.tap do |r|
          r.x = x
          r.y = y
          r.width = w
          r.height = h
          r.fill = colors[:bg]
          r.stroke = colors[:border]
          r.stroke_width = '2'
          r.rx = 5
          r.ry = 5
        end
        group.children << rect

        # Render labels
        render_element_labels(element, x, y + 20, w, colors[:text], group)
      end

      def render_component_element(element, group)
        x = element[:x]
        y = element[:y]
        w = element[:width] || COMPONENT_WIDTH
        h = element[:height] || COMPONENT_HEIGHT

        colors = C4_COLORS[:component]

        # Component box
        rect = Svg::Rect.new.tap do |r|
          r.x = x
          r.y = y
          r.width = w
          r.height = h
          r.fill = colors[:bg]
          r.stroke = colors[:border]
          r.stroke_width = '2'
          r.rx = 3
          r.ry = 3
        end
        group.children << rect

        # Render labels
        render_element_labels(element, x, y + 15, w, colors[:text], group)
      end

      def render_element_labels(element, x, y, width, text_color, group)
        labels = element[:labels] || []
        current_y = y

        labels.each_with_index do |label, index|
          font_size = case index
                      when 0 # Main label
                        '14'
                      when 1 # Description
                        '11'
                      else # Technology
                        '10'
                      end

          font_weight = index.zero? ? 'bold' : 'normal'
          font_style = index == 2 ? 'italic' : 'normal'

          text = Svg::Text.new.tap do |t|
            t.x = x + width / 2
            t.y = current_y
            t.content = label[:text]
            t.fill = text_color
            t.font_family = 'Arial, sans-serif'
            t.font_size = font_size
            t.font_weight = font_weight
            t.font_style = font_style
            t.text_anchor = 'middle'
          end
          group.children << text

          current_y += LINE_HEIGHT
        end
      end

      def render_relationships(edges, nodes, svg)
        # Build node position map
        node_positions = {}
        traverse_children(nodes) do |node|
          next if node[:metadata]&.[](:boundary_type)

          node_positions[node[:id]] = {
            x: node[:x],
            y: node[:y],
            width: node[:width],
            height: node[:height]
          }
        end

        edges.each do |edge|
          render_relationship(edge, node_positions, svg)
        end
      end

      def render_relationship(edge, positions, svg)
        source_id = edge[:sources]&.first
        target_id = edge[:targets]&.first

        return unless source_id && target_id

        source_pos = positions[source_id]
        target_pos = positions[target_id]

        return unless source_pos && target_pos

        # Calculate connection points (center of elements)
        x1 = source_pos[:x] + source_pos[:width] / 2
        y1 = source_pos[:y] + source_pos[:height] / 2
        x2 = target_pos[:x] + target_pos[:width] / 2
        y2 = target_pos[:y] + target_pos[:height] / 2

        group = Svg::Group.new.tap do |g|
          g.id = edge[:id]
        end

        # Draw relationship line
        line = Svg::Line.new.tap do |l|
          l.x1 = x1
          l.y1 = y1
          l.x2 = x2 - ARROW_SIZE
          l.y2 = y2
          l.stroke = '#707070'
          l.stroke_width = '2'
        end
        group.children << line

        # Draw arrowhead
        render_arrowhead(x1, y1, x2, y2, group)

        # Draw bidirectional arrow if needed
        if edge[:metadata]&.[](:bidirectional)
          render_arrowhead(x2, y2, x1, y1, group)
        end

        # Render relationship labels
        if edge[:labels] && !edge[:labels].empty?
          render_relationship_labels(x1, y1, x2, y2, edge[:labels], group)
        end

        svg << group
      end

      def render_arrowhead(x1, _y1, x2, y2, group)
        # Calculate arrow direction
        dx = x2 - x1
        angle = dx.positive? ? 0 : 180

        # Arrowhead points
        points = if angle.zero?
                   [
                     "#{x2},#{y2}",
                     "#{x2 - ARROW_SIZE},#{y2 - ARROW_SIZE / 2}",
                     "#{x2 - ARROW_SIZE},#{y2 + ARROW_SIZE / 2}"
                   ].join(' ')
                 else
                   [
                     "#{x2},#{y2}",
                     "#{x2 + ARROW_SIZE},#{y2 - ARROW_SIZE / 2}",
                     "#{x2 + ARROW_SIZE},#{y2 + ARROW_SIZE / 2}"
                   ].join(' ')
                 end

        polygon = Svg::Polygon.new.tap do |p|
          p.points = points
          p.fill = '#707070'
          p.stroke = '#707070'
        end
        group.children << polygon
      end

      def render_relationship_labels(x1, y1, x2, y2, labels, group)
        # Position label above the line
        label_x = (x1 + x2) / 2
        label_y = (y1 + y2) / 2 - 15

        labels.each_with_index do |label, index|
          font_size = index.zero? ? '12' : '10'
          offset_y = index * 14

          text = Svg::Text.new.tap do |t|
            t.x = label_x
            t.y = label_y + offset_y
            t.content = label[:text]
            t.fill = '#000000'
            t.font_family = 'Arial, sans-serif'
            t.font_size = font_size
            t.text_anchor = 'middle'
          end
          group.children << text
        end
      end
    end
  end
end