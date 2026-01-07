# frozen_string_literal: true

require_relative 'base'

module Sirena
  module Renderer
    # Requirement diagram renderer for converting positioned layouts to SVG.
    #
    # Converts a positioned requirement diagram layout into SVG using the Svg
    # builder classes. Handles requirements with properties, elements, and
    # relationships between them.
    #
    # @example Render a requirement diagram
    #   renderer = RequirementRenderer.new
    #   svg = renderer.render(layout)
    class RequirementRenderer < Base
      # Risk level color mapping
      RISK_COLORS = {
        'high' => '#ff6b6b',
        'medium' => '#ffd93d',
        'low' => '#6bcf7f'
      }.freeze

      # Requirement type labels
      REQUIREMENT_TYPE_LABELS = {
        'requirement' => 'Requirement',
        'functionalRequirement' => 'Functional Req',
        'interfaceRequirement' => 'Interface Req',
        'performanceRequirement' => 'Performance Req',
        'physicalRequirement' => 'Physical Req',
        'designConstraint' => 'Design Constraint'
      }.freeze

      # Renders a positioned layout to SVG.
      #
      # @param layout [Hash] positioned layout with requirement and element positions
      # @return [Svg::Document] the rendered SVG document
      def render(layout)
        svg = create_document_from_layout(layout)

        # Render relationships first (so they appear under nodes)
        render_relationships(layout, svg) if layout[:relationships]

        # Render requirements
        render_requirements(layout, svg) if layout[:requirements]

        # Render elements
        render_elements(layout, svg) if layout[:elements]

        svg
      end

      protected

      def create_document_from_layout(layout)
        width = layout[:width] || 800
        height = layout[:height] || 600

        Svg::Document.new(width: width, height: height)
      end

      def render_requirements(layout, svg)
        layout[:requirements].each do |_req_name, req_info|
          render_requirement(req_info, svg)
        end
      end

      def render_requirement(req_info, svg)
        requirement = req_info[:requirement]
        x = req_info[:x]
        y = req_info[:y]
        width = req_info[:width]
        height = req_info[:height]

        # Create group for requirement
        group = Svg::Group.new.tap do |g|
          g.id = "requirement-#{requirement.name}"
        end

        # Draw main box
        box = create_requirement_box(x, y, width, height, requirement)
        group.children << box

        # Draw header section with type
        header_height = 30
        header = create_requirement_header(x, y, width, header_height, requirement)
        group.children << header

        # Add text content
        text_y = y + header_height + 15
        line_height = 16

        # ID
        if requirement.id
          id_text = create_property_text(x + 10, text_y, "ID: #{requirement.id}")
          group.children << id_text
          text_y += line_height
        end

        # Text
        if requirement.text
          text_lines = wrap_text(requirement.text, width - 20, 12)
          text_lines.each do |line|
            text_element = create_property_text(x + 10, text_y, line)
            group.children << text_element
            text_y += line_height
          end
          text_y += 5
        end

        # Risk
        if requirement.risk
          risk_text = create_property_text(x + 10, text_y, "Risk: #{requirement.risk.capitalize}")
          risk_text.fill = get_risk_color(requirement.risk)
          risk_text.font_weight = 'bold'
          group.children << risk_text
          text_y += line_height
        end

        # Verify method
        if requirement.verifymethod
          verify_text = create_property_text(x + 10, text_y, "Verify: #{requirement.verifymethod.capitalize}")
          group.children << verify_text
        end

        svg << group
      end

      def create_requirement_box(x, y, width, height, requirement)
        Svg::Rect.new.tap do |rect|
          rect.x = x
          rect.y = y
          rect.width = width
          rect.height = height
          rect.fill = theme_color(:node_fill) || '#f9f9f9'
          rect.stroke = get_risk_color(requirement.risk) || theme_color(:border_color) || '#333'
          rect.stroke_width = '2'
          rect.rx = '5'
          rect.ry = '5'
        end
      end

      def create_requirement_header(x, y, width, height, requirement)
        group = Svg::Group.new

        # Header background
        header_bg = Svg::Rect.new.tap do |rect|
          rect.x = x
          rect.y = y
          rect.width = width
          rect.height = height
          rect.fill = get_risk_color(requirement.risk) || theme_color(:node_fill) || '#e0e0e0'
          rect.opacity = '0.3'
        end
        group.children << header_bg

        # Type label
        type_label = REQUIREMENT_TYPE_LABELS[requirement.type] || requirement.type
        type_text = Svg::Text.new.tap do |text|
          text.x = x + 10
          text.y = y + height / 2
          text.content = type_label
          text.fill = theme_color(:text_color) || '#000'
          text.font_size = '12'
          text.font_weight = 'bold'
          text.dominant_baseline = 'middle'
        end
        group.children << type_text

        # Name on the right
        name_text = Svg::Text.new.tap do |text|
          text.x = x + width - 10
          text.y = y + height / 2
          text.content = requirement.name
          text.fill = theme_color(:text_color) || '#000'
          text.font_size = '11'
          text.text_anchor = 'end'
          text.dominant_baseline = 'middle'
        end
        group.children << name_text

        group
      end

      def render_elements(layout, svg)
        layout[:elements].each do |_elem_name, elem_info|
          render_element(elem_info, svg)
        end
      end

      def render_element(elem_info, svg)
        element = elem_info[:element]
        x = elem_info[:x]
        y = elem_info[:y]
        width = elem_info[:width]
        height = elem_info[:height]

        # Create group for element
        group = Svg::Group.new.tap do |g|
          g.id = "element-#{element.name}"
        end

        # Draw hexagon shape for elements
        hexagon = create_hexagon(x, y, width, height)
        group.children << hexagon

        # Add name
        name_text = Svg::Text.new.tap do |text|
          text.x = x + width / 2
          text.y = y + height / 2 - 10
          text.content = element.name
          text.fill = theme_color(:text_color) || '#000'
          text.font_size = '14'
          text.font_weight = 'bold'
          text.text_anchor = 'middle'
          text.dominant_baseline = 'middle'
        end
        group.children << name_text

        # Add type if present
        if element.type
          type_text = Svg::Text.new.tap do |text|
            text.x = x + width / 2
            text.y = y + height / 2 + 10
            text.content = "Type: #{element.type}"
            text.fill = theme_color(:text_color) || '#666'
            text.font_size = '11'
            text.text_anchor = 'middle'
            text.dominant_baseline = 'middle'
          end
          group.children << type_text
        end

        svg << group
      end

      def create_hexagon(x, y, width, height)
        cx = x + width / 2
        cy = y + height / 2
        w = width / 2
        h = height / 2

        points = [
          "#{cx - w},#{cy}",
          "#{cx - w/2},#{cy - h}",
          "#{cx + w/2},#{cy - h}",
          "#{cx + w},#{cy}",
          "#{cx + w/2},#{cy + h}",
          "#{cx - w/2},#{cy + h}"
        ].join(' ')

        Svg::Polygon.new.tap do |polygon|
          polygon.points = points
          polygon.fill = theme_color(:node_fill) || '#e0f2f1'
          polygon.stroke = theme_color(:border_color) || '#00796b'
          polygon.stroke_width = '2'
        end
      end

      def render_relationships(layout, svg)
        layout[:relationships].each do |rel_info|
          render_relationship(rel_info, svg)
        end
      end

      def render_relationship(rel_info, svg)
        # Calculate path for relationship
        path_data = calculate_relationship_path(rel_info)

        # Create path element
        path = Svg::Path.new.tap do |p|
          p.d = path_data
          p.fill = 'none'
          p.stroke = theme_color(:edge_color) || '#666'
          p.stroke_width = '2'
          p.marker_end = 'url(#arrowhead)'
        end

        # Create group for relationship
        group = Svg::Group.new.tap do |g|
          g.id = "relationship-#{rel_info[:source]}-#{rel_info[:target]}"
        end

        group.children << path

        # Add label for relationship type
        if rel_info[:type]
          mid_x = (rel_info[:from_x] + rel_info[:to_x]) / 2
          mid_y = (rel_info[:from_y] + rel_info[:to_y]) / 2

          label_bg = Svg::Rect.new.tap do |rect|
            label_width = rel_info[:type].length * 7
            rect.x = mid_x - label_width / 2
            rect.y = mid_y - 10
            rect.width = label_width
            rect.height = 18
            rect.fill = '#fff'
            rect.stroke = theme_color(:edge_color) || '#666'
            rect.stroke_width = '1'
            rect.rx = '3'
          end
          group.children << label_bg

          label = Svg::Text.new.tap do |text|
            text.x = mid_x
            text.y = mid_y
            text.content = rel_info[:type]
            text.fill = theme_color(:text_color) || '#000'
            text.font_size = '10'
            text.text_anchor = 'middle'
            text.dominant_baseline = 'middle'
          end
          group.children << label
        end

        svg << group
      end

      def calculate_relationship_path(rel_info)
        from_x = rel_info[:from_x]
        from_y = rel_info[:from_y]
        to_x = rel_info[:to_x]
        to_y = rel_info[:to_y]

        # Use bezier curve for better aesthetics
        control_offset = (to_y - from_y).abs / 3

        "M #{from_x} #{from_y} C #{from_x} #{from_y + control_offset}, " \
          "#{to_x} #{to_y - control_offset}, #{to_x} #{to_y}"
      end

      def create_property_text(x, y, content)
        Svg::Text.new.tap do |text|
          text.x = x
          text.y = y
          text.content = content
          text.fill = theme_color(:text_color) || '#000'
          text.font_size = '12'
        end
      end

      def get_risk_color(risk)
        return nil unless risk

        RISK_COLORS[risk.downcase] || theme_color(:border_color) || '#666'
      end

      def wrap_text(text, max_width, font_size)
        # Simple text wrapping
        words = text.split(' ')
        lines = []
        current_line = []

        chars_per_line = (max_width / (font_size * 0.6)).to_i

        words.each do |word|
          test_line = (current_line + [word]).join(' ')
          if test_line.length <= chars_per_line
            current_line << word
          else
            lines << current_line.join(' ') unless current_line.empty?
            current_line = [word]
          end
        end

        lines << current_line.join(' ') unless current_line.empty?
        lines
      end
    end
  end
end