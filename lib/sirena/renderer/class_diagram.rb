# frozen_string_literal: true

require_relative 'base'

module Sirena
  module Renderer
    # Class diagram renderer for converting graphs to SVG.
    #
    # Converts a laid-out graph structure (with computed positions) into
    # SVG using the Svg builder classes. Handles UML class boxes with
    # compartments, various relationship types with appropriate arrow
    # styles, and cardinality labels.
    #
    # @example Render a class diagram
    #   renderer = ClassDiagramRenderer.new
    #   svg = renderer.render(laid_out_graph)
    class ClassDiagramRenderer < Base
      # Font size for class names
      CLASS_NAME_FONT_SIZE = 16

      # Font size for attributes and methods
      MEMBER_FONT_SIZE = 12

      # Font size for stereotypes
      STEREOTYPE_FONT_SIZE = 11

      # Line height for text
      LINE_HEIGHT = 18

      # Padding within class boxes
      BOX_PADDING = 10

      # Arrow/marker dimensions
      ARROW_SIZE = 10
      DIAMOND_SIZE = 12

      # Renders a laid-out graph to SVG.
      #
      # @param graph [Hash] laid-out graph with node positions
      # @return [Svg::Document] the rendered SVG document
      def render(graph)
        svg = create_document(graph)

        # Add marker definitions
        add_markers(svg)

        # Render edges first (so they appear under nodes)
        render_relationships(graph, svg) if graph[:edges]

        # Render class boxes
        render_classes(graph, svg) if graph[:children]

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

      def add_markers(svg)
        # Add definitions for various arrow types
        defs = Svg::Group.new
        defs.id = 'defs'

        # Inheritance marker (hollow triangle)
        add_inheritance_marker(defs)

        # Composition marker (filled diamond)
        add_composition_marker(defs)

        # Aggregation marker (hollow diamond)
        add_aggregation_marker(defs)

        svg << defs
      end

      def add_inheritance_marker(defs)
        # This will be rendered as a hollow triangle in render_relationship
      end

      def add_composition_marker(defs)
        # This will be rendered as a filled diamond in render_relationship
      end

      def add_aggregation_marker(defs)
        # This will be rendered as a hollow diamond in render_relationship
      end

      def render_classes(graph, svg)
        graph[:children].each do |node|
          render_class(node, svg)
        end
      end

      def render_class(node, svg)
        x = node[:x] || 0
        y = node[:y] || 0
        width = node[:width] || 150
        height = node[:height] || 100

        metadata = node[:metadata] || {}

        # Create group for the class
        group = Svg::Group.new.tap do |g|
          g.id = "class-#{node[:id]}"
        end

        # Render outer box
        box = Svg::Rect.new.tap do |r|
          r.x = x
          r.y = y
          r.width = width
          r.height = height
          r.fill = '#ffffff'
          r.stroke = '#000000'
          r.stroke_width = '2'
          r.rx = 3
          r.ry = 3
        end
        group.children << box

        # Render compartment separators and content
        render_class_content(node, metadata, group)

        svg << group
      end

      def render_class_content(node, metadata, group)
        x = node[:x] || 0
        y = node[:y] || 0
        width = node[:width] || 150

        current_y = y + BOX_PADDING

        # Render stereotype if present
        stereotype = metadata[:stereotype]
        current_y = render_stereotype(x, current_y, width, stereotype, group) if stereotype && !stereotype.empty?

        # Render class name
        name = metadata[:name] || node[:id]
        current_y = render_class_name(x, current_y, width, name, group)

        # Add separator after name
        separator_y = current_y + 5
        separator = Svg::Line.new.tap do |l|
          l.x1 = x
          l.y1 = separator_y
          l.x2 = x + width
          l.y2 = separator_y
          l.stroke = '#000000'
          l.stroke_width = '1'
        end
        group.children << separator
        current_y = separator_y + 10

        # Render attributes
        attributes = metadata[:attributes] || []
        unless attributes.empty?
          current_y = render_attributes(x, current_y, width, attributes, group)

          # Add separator after attributes
          separator_y = current_y + 5
          separator = Svg::Line.new.tap do |l|
            l.x1 = x
            l.y1 = separator_y
            l.x2 = x + width
            l.y2 = separator_y
            l.stroke = '#000000'
            l.stroke_width = '1'
          end
          group.children << separator
          current_y = separator_y + 10
        end

        # Render methods
        methods = metadata[:methods] || []
        render_methods(x, current_y, width, methods, group) unless
          methods.empty?
      end

      def render_stereotype(x, y, width, stereotype, group)
        text = Svg::Text.new.tap do |t|
          t.x = x + width / 2
          t.y = y
          t.content = "<<#{stereotype}>>"
          t.fill = '#000000'
          t.font_family = 'Arial, sans-serif'
          t.font_size = STEREOTYPE_FONT_SIZE.to_s
          t.text_anchor = 'middle'
        end
        group.children << text
        y + LINE_HEIGHT
      end

      def render_class_name(x, y, width, name, group)
        text = Svg::Text.new.tap do |t|
          t.x = x + width / 2
          t.y = y
          t.content = name
          t.fill = '#000000'
          t.font_family = 'Arial, sans-serif'
          t.font_size = CLASS_NAME_FONT_SIZE.to_s
          t.text_anchor = 'middle'
          t.font_weight = 'bold'
        end
        group.children << text
        y + LINE_HEIGHT
      end

      def render_attributes(x, y, _width, attributes, group)
        current_y = y

        attributes.each do |attr|
          visibility = visibility_symbol(attr[:visibility])
          attr_text = "#{visibility} #{attr[:name]}"
          attr_text += ": #{attr[:type]}" if attr[:type] &&
                                             !attr[:type].empty?

          text = Svg::Text.new.tap do |t|
            t.x = x + BOX_PADDING
            t.y = current_y
            t.content = attr_text
            t.fill = '#000000'
            t.font_family = 'monospace'
            t.font_size = MEMBER_FONT_SIZE.to_s
          end
          group.children << text
          current_y += LINE_HEIGHT
        end

        current_y
      end

      def render_methods(x, y, _width, methods, group)
        current_y = y

        methods.each do |method|
          visibility = visibility_symbol(method[:visibility])
          method_text = "#{visibility} #{method[:name]}"
          method_text += "(#{method[:parameters]})" if method[:parameters]
          method_text += ": #{method[:return_type]}" if method[:return_type]

          text = Svg::Text.new.tap do |t|
            t.x = x + BOX_PADDING
            t.y = current_y
            t.content = method_text
            t.fill = '#000000'
            t.font_family = 'monospace'
            t.font_size = MEMBER_FONT_SIZE.to_s
          end
          group.children << text
          current_y += LINE_HEIGHT
        end

        current_y
      end

      def visibility_symbol(visibility)
        case visibility
        when 'public' then '+'
        when 'private' then '-'
        when 'protected' then '#'
        when 'package' then '~'
        else '+'
        end
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
        rel_type = metadata[:relationship_type] || 'association'

        # Create group for the relationship
        group = Svg::Group.new.tap do |g|
          g.id = "rel-#{edge[:id]}"
        end

        # Calculate connection points
        source_point = calculate_connection_point(source, target)
        target_point = calculate_connection_point(target, source)

        # Render the line
        render_relationship_line(source_point, target_point, rel_type, group)

        # Render arrow/marker at target
        render_relationship_marker(source_point, target_point, rel_type, group)

        # Render labels if present
        render_relationship_labels(edge, source_point, target_point, group)

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
        if dx.abs < 0.001 && dy.abs < 0.001
          # Same position - use center
          return { x: from_cx, y: from_cy }
        end

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
          l.stroke = '#000000'
          l.stroke_width = '2'
          l.stroke_dasharray = '5,5' if rel_type == 'dependency'
        end
        group.children << line
      end

      def render_relationship_marker(from, to, rel_type, group)
        case rel_type
        when 'inheritance', 'realization'
          render_triangle_marker(from, to, rel_type == 'inheritance', group)
        when 'composition'
          render_diamond_marker(from, to, true, group)
        when 'aggregation'
          render_diamond_marker(from, to, false, group)
        end
      end

      def render_triangle_marker(from, to, filled, group)
        dx = to[:x] - from[:x]
        dy = to[:y] - from[:y]
        angle = Math.atan2(dy, dx)

        # Triangle points
        tip_x = to[:x]
        tip_y = to[:y]
        base_length = ARROW_SIZE
        base1_x = tip_x - base_length * Math.cos(angle + Math::PI / 6)
        base1_y = tip_y - base_length * Math.sin(angle + Math::PI / 6)
        base2_x = tip_x - base_length * Math.cos(angle - Math::PI / 6)
        base2_y = tip_y - base_length * Math.sin(angle - Math::PI / 6)

        points = "#{tip_x},#{tip_y} #{base1_x},#{base1_y} " \
                 "#{base2_x},#{base2_y}"

        polygon = Svg::Polygon.new.tap do |p|
          p.points = points
          p.fill = filled ? '#000000' : '#ffffff'
          p.stroke = '#000000'
          p.stroke_width = '2'
        end
        group.children << polygon
      end

      def render_diamond_marker(from, to, filled, group)
        dx = to[:x] - from[:x]
        dy = to[:y] - from[:y]
        angle = Math.atan2(dy, dx)

        # Diamond center at connection point
        cx = from[:x]
        cy = from[:y]
        size = DIAMOND_SIZE

        # Diamond points
        tip_x = cx + size * Math.cos(angle)
        tip_y = cy + size * Math.sin(angle)
        left_x = cx + size / 2 * Math.cos(angle + Math::PI / 2)
        left_y = cy + size / 2 * Math.sin(angle + Math::PI / 2)
        back_x = cx - size * Math.cos(angle)
        back_y = cy - size * Math.sin(angle)
        right_x = cx + size / 2 * Math.cos(angle - Math::PI / 2)
        right_y = cy + size / 2 * Math.sin(angle - Math::PI / 2)

        points = "#{tip_x},#{tip_y} #{left_x},#{left_y} " \
                 "#{back_x},#{back_y} #{right_x},#{right_y}"

        polygon = Svg::Polygon.new.tap do |p|
          p.points = points
          p.fill = filled ? '#000000' : '#ffffff'
          p.stroke = '#000000'
          p.stroke_width = '2'
        end
        group.children << polygon
      end

      def render_relationship_labels(edge, from, to, group)
        labels = edge[:labels] || []
        return if labels.empty?

        # Main label in the middle
        main_label = labels.find { |l| !l[:position] }
        if main_label
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

        # Source cardinality
        source_label = labels.find { |l| l[:position] == 'source' }
        if source_label
          text = Svg::Text.new.tap do |t|
            t.x = from[:x] + 5
            t.y = from[:y] - 5
            t.content = source_label[:text]
            t.fill = '#000000'
            t.font_family = 'Arial, sans-serif'
            t.font_size = '10'
          end
          group.children << text
        end

        # Target cardinality
        target_label = labels.find { |l| l[:position] == 'target' }
        return unless target_label

        text = Svg::Text.new.tap do |t|
          t.x = to[:x] - 5
          t.y = to[:y] - 5
          t.content = target_label[:text]
          t.fill = '#000000'
          t.font_family = 'Arial, sans-serif'
          t.font_size = '10'
          t.text_anchor = 'end'
        end
        group.children << text
      end
    end
  end
end
