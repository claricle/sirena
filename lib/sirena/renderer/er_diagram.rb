# frozen_string_literal: true

require_relative 'base'

module Sirena
  module Renderer
    # ER diagram renderer for converting graphs to SVG.
    #
    # Converts a laid-out graph structure (with computed positions) into
    # SVG using the Svg builder classes. Handles ER entity boxes with
    # attributes, PK/FK markers, and relationship lines with crow's foot
    # cardinality notation.
    #
    # @example Render an ER diagram
    #   renderer = ErDiagramRenderer.new
    #   svg = renderer.render(laid_out_graph)
    class ErDiagramRenderer < Base
      # Font size for entity names
      ENTITY_NAME_FONT_SIZE = 16

      # Font size for attributes
      ATTRIBUTE_FONT_SIZE = 12

      # Line height for text
      LINE_HEIGHT = 18

      # Padding within entity boxes
      BOX_PADDING = 10

      # Cardinality symbol size
      CARDINALITY_SIZE = 15

      # Renders a laid-out graph to SVG.
      #
      # @param graph [Hash] laid-out graph with node positions
      # @return [Svg::Document] the rendered SVG document
      def render(graph)
        svg = create_document(graph)

        # Render edges first (so they appear under nodes)
        render_relationships(graph, svg) if graph[:edges]

        # Render entity boxes
        render_entities(graph, svg) if graph[:children]

        svg
      end

      protected

      def calculate_width(graph)
        return 800 unless graph[:children]

        max_x = graph[:children].map do |node|
          (node[:x] || 0) + (node[:width] || 150)
        end.max || 800

        max_x + 40
      end

      def calculate_height(graph)
        return 600 unless graph[:children]

        max_y = graph[:children].map do |node|
          (node[:y] || 0) + (node[:height] || 100)
        end.max || 600

        max_y + 40
      end

      def render_entities(graph, svg)
        graph[:children].each do |node|
          render_entity(node, svg)
        end
      end

      def render_entity(node, svg)
        x = node[:x] || 0
        y = node[:y] || 0
        width = node[:width] || 150
        height = node[:height] || 100

        metadata = node[:metadata] || {}

        # Create group for the entity
        group = Svg::Group.new.tap do |g|
          g.id = "entity-#{node[:id]}"
        end

        # Render outer box
        box = Svg::Rect.new.tap do |r|
          r.x = x
          r.y = y
          r.width = width
          r.height = height
          r.fill = '#f9f9f9'
          r.stroke = '#333333'
          r.stroke_width = '2'
        end
        group.children << box

        # Render entity content
        render_entity_content(node, metadata, group)

        svg << group
      end

      def render_entity_content(node, metadata, group)
        x = node[:x] || 0
        y = node[:y] || 0
        width = node[:width] || 150

        current_y = y + BOX_PADDING + ENTITY_NAME_FONT_SIZE

        # Render entity name
        name = metadata[:name] || node[:id]
        text = Svg::Text.new.tap do |t|
          t.x = x + width / 2
          t.y = current_y
          t.content = name
          t.fill = '#000000'
          t.font_family = 'Arial, sans-serif'
          t.font_size = ENTITY_NAME_FONT_SIZE.to_s
          t.text_anchor = 'middle'
          t.font_weight = 'bold'
        end
        group.children << text

        # Add separator after name
        current_y += LINE_HEIGHT
        separator = Svg::Line.new.tap do |l|
          l.x1 = x
          l.y1 = current_y
          l.x2 = x + width
          l.y2 = current_y
          l.stroke = '#333333'
          l.stroke_width = '1'
        end
        group.children << separator

        # Render attributes
        attributes = metadata[:attributes] || []
        current_y += BOX_PADDING
        attributes.each do |attr|
          current_y = render_attribute(x, current_y, width, attr, group)
        end
      end

      def render_attribute(x, y, _width, attribute, group)
        # Build attribute text with key type marker
        parts = []
        parts << attribute[:key_type] if attribute[:key_type] &&
                                         !attribute[:key_type].empty?
        parts << attribute[:name]
        parts << attribute[:attribute_type] if attribute[:attribute_type] &&
                                               !attribute[:attribute_type]
                                               .empty?

        attr_text = parts.join(' ')

        text = Svg::Text.new.tap do |t|
          t.x = x + BOX_PADDING
          t.y = y + ATTRIBUTE_FONT_SIZE
          t.content = attr_text
          t.fill = '#000000'
          t.font_family = 'monospace'
          t.font_size = ATTRIBUTE_FONT_SIZE.to_s
        end
        group.children << text

        y + LINE_HEIGHT
      end

      def render_relationships(graph, svg)
        graph[:edges].each do |edge|
          render_relationship(edge, graph, svg)
        end
      end

      def render_relationship(edge, graph, svg)
        source = find_node(graph, edge[:sources]&.first)
        target = find_node(graph, edge[:targets]&.first)

        return unless source && target

        metadata = edge[:metadata] || {}

        # Create group for the relationship
        group = Svg::Group.new.tap do |g|
          g.id = "rel-#{edge[:id]}"
        end

        # Calculate connection points
        source_point = calculate_connection_point(source, target)
        target_point = calculate_connection_point(target, source)

        # Render the line
        rel_type = metadata[:relationship_type] || 'non-identifying'
        render_relationship_line(
          source_point,
          target_point,
          rel_type,
          group
        )

        # Render cardinality markers
        card_from = metadata[:cardinality_from]
        card_to = metadata[:cardinality_to]

        if card_from
          render_cardinality(
            source_point,
            target_point,
            card_from,
            :source,
            group
          )
        end
        if card_to
          render_cardinality(
            target_point,
            source_point,
            card_to,
            :target,
            group
          )
        end

        # Render label if present
        render_relationship_label(edge, source_point, target_point, group)

        svg << group
      end

      def find_node(graph, node_id)
        return nil unless graph[:children] && node_id

        graph[:children].find { |n| n[:id] == node_id }
      end

      def calculate_connection_point(from_node, to_node)
        from_cx = (from_node[:x] || 0) + (from_node[:width] || 150) / 2
        from_cy = (from_node[:y] || 0) + (from_node[:height] || 100) / 2
        to_cx = (to_node[:x] || 0) + (to_node[:width] || 150) / 2
        to_cy = (to_node[:y] || 0) + (to_node[:height] || 100) / 2

        # Determine which edge of the box to connect to
        from_x = from_node[:x] || 0
        from_y = from_node[:y] || 0
        from_w = from_node[:width] || 150
        from_h = from_node[:height] || 100

        # Calculate intersection with box edge
        dx = to_cx - from_cx
        dy = to_cy - from_cy

        # Handle edge cases
        return { x: from_cx, y: from_cy } if dx.abs < 0.001 && dy.abs < 0.001

        # Find intersection point
        if dx.abs > dy.abs
          # Connect left/right edge
          x = dx.positive? ? from_x + from_w : from_x
          y = dy.abs < 0.001 ? from_cy : from_cy + (dy / dx) * (x - from_cx)
        else
          # Connect top/bottom edge
          y = dy.positive? ? from_y + from_h : from_y
          x = dx.abs < 0.001 ? from_cx : from_cx + (dx / dy) * (y - from_cy)
        end

        { x: x, y: y }
      end

      def render_relationship_line(from, to, rel_type, group)
        line = Svg::Line.new.tap do |l|
          l.x1 = from[:x]
          l.y1 = from[:y]
          l.x2 = to[:x]
          l.y2 = to[:y]
          l.stroke = '#333333'
          l.stroke_width = '2'
          l.stroke_dasharray = '5,5' if rel_type == 'non-identifying'
        end
        group.children << line
      end

      def render_cardinality(point, opposite_point, cardinality, _side, group)
        case cardinality
        when 'one'
          render_one_marker(point, opposite_point, group)
        when 'zero_or_more'
          render_zero_or_more_marker(point, opposite_point, group)
        when 'one_or_more'
          render_one_or_more_marker(point, opposite_point, group)
        when 'zero_or_one'
          render_zero_or_one_marker(point, opposite_point, group)
        end
      end

      def render_one_marker(point, opposite_point, group)
        # Single perpendicular line (|)
        dx = opposite_point[:x] - point[:x]
        dy = opposite_point[:y] - point[:y]
        angle = Math.atan2(dy, dx)

        # Perpendicular angle
        perp_angle = angle + Math::PI / 2

        # Calculate perpendicular line endpoints
        half_size = CARDINALITY_SIZE / 2
        x1 = point[:x] + half_size * Math.cos(perp_angle)
        y1 = point[:y] + half_size * Math.sin(perp_angle)
        x2 = point[:x] - half_size * Math.cos(perp_angle)
        y2 = point[:y] - half_size * Math.sin(perp_angle)

        line = Svg::Line.new.tap do |l|
          l.x1 = x1
          l.y1 = y1
          l.x2 = x2
          l.y2 = y2
          l.stroke = '#333333'
          l.stroke_width = '2'
        end
        group.children << line
      end

      def render_zero_or_more_marker(point, opposite_point, group)
        # Circle + crow's foot (o<)
        render_circle_marker(point, opposite_point, group)
        render_crows_foot(point, opposite_point, group)
      end

      def render_one_or_more_marker(point, opposite_point, group)
        # Line + crow's foot (|<)
        render_one_marker(point, opposite_point, group)
        render_crows_foot(point, opposite_point, group)
      end

      def render_zero_or_one_marker(point, opposite_point, group)
        # Circle + line (o|)
        render_circle_marker(point, opposite_point, group)
        render_one_marker(point, opposite_point, group)
      end

      def render_circle_marker(point, opposite_point, group)
        dx = opposite_point[:x] - point[:x]
        dy = opposite_point[:y] - point[:y]
        angle = Math.atan2(dy, dx)

        # Offset the circle along the line
        offset = CARDINALITY_SIZE / 2
        cx = point[:x] + offset * Math.cos(angle)
        cy = point[:y] + offset * Math.sin(angle)

        circle = Svg::Circle.new.tap do |c|
          c.cx = cx
          c.cy = cy
          c.r = CARDINALITY_SIZE / 3
          c.fill = 'none'
          c.stroke = '#333333'
          c.stroke_width = '2'
        end
        group.children << circle
      end

      def render_crows_foot(point, opposite_point, group)
        # Three lines forming crow's foot (< shape)
        dx = opposite_point[:x] - point[:x]
        dy = opposite_point[:y] - point[:y]
        angle = Math.atan2(dy, dx)

        # Offset the crow's foot along the line
        offset = CARDINALITY_SIZE
        base_x = point[:x] + offset * Math.cos(angle)
        base_y = point[:y] + offset * Math.sin(angle)

        # Create three lines at angles
        angles = [-Math::PI / 4, 0, Math::PI / 4]
        angles.each do |angle_offset|
          line_angle = angle + Math::PI + angle_offset
          end_x = base_x + CARDINALITY_SIZE * Math.cos(line_angle)
          end_y = base_y + CARDINALITY_SIZE * Math.sin(line_angle)

          line = Svg::Line.new.tap do |l|
            l.x1 = base_x
            l.y1 = base_y
            l.x2 = end_x
            l.y2 = end_y
            l.stroke = '#333333'
            l.stroke_width = '2'
          end
          group.children << line
        end
      end

      def render_relationship_label(edge, from, to, group)
        labels = edge[:labels] || []
        main_label = labels.find { |l| !l[:position] }
        return unless main_label

        mid_x = (from[:x] + to[:x]) / 2
        mid_y = (from[:y] + to[:y]) / 2

        text = Svg::Text.new.tap do |t|
          t.x = mid_x
          t.y = mid_y - 5
          t.content = main_label[:text]
          t.fill = '#000000'
          t.font_family = 'Arial, sans-serif'
          t.font_size = '11'
          t.text_anchor = 'middle'
        end
        group.children << text
      end
    end
  end
end
