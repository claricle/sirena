# frozen_string_literal: true

require_relative 'base'
require_relative '../diagram/requirement'

module Sirena
  module Transform
    # Requirement diagram transformer for converting requirement models to positioned layouts.
    #
    # Converts a requirement diagram model into a positioned layout structure.
    # Handles requirement and element positioning, relationship routing,
    # and hierarchical layout based on dependencies.
    #
    # @example Transform a requirement diagram
    #   transform = RequirementTransform.new
    #   layout = transform.to_layout(requirement_diagram)
    class RequirementTransform < Base
      # Default dimensions
      DEFAULT_REQ_WIDTH = 180
      DEFAULT_REQ_HEIGHT = 140
      DEFAULT_ELEM_WIDTH = 150
      DEFAULT_ELEM_HEIGHT = 80
      DEFAULT_SPACING_X = 100
      DEFAULT_SPACING_Y = 80
      DEFAULT_PADDING = 20

      # Converts a requirement diagram to a positioned layout structure.
      #
      # @param diagram [Diagram::RequirementDiagram] the requirement diagram to transform
      # @return [Hash] positioned layout hash
      # @raise [TransformError] if diagram is invalid
      def to_graph(diagram)
        raise TransformError, 'Diagram cannot be nil' if diagram.nil?

        # Calculate positions for requirements and elements
        nodes_layout = calculate_node_positions(diagram)

        # Calculate relationship routes
        relationships_layout = calculate_relationships(diagram, nodes_layout)

        {
          requirements: nodes_layout[:requirements],
          elements: nodes_layout[:elements],
          relationships: relationships_layout,
          width: nodes_layout[:width],
          height: nodes_layout[:height]
        }
      end

      private

      def calculate_node_positions(diagram)
        requirements = diagram.requirements
        elements = diagram.elements
        relationships = diagram.relationships

        # Build dependency graph to determine layout
        levels = build_dependency_levels(requirements, elements, relationships)

        positioned_requirements = {}
        positioned_elements = {}

        current_y = DEFAULT_PADDING
        max_width = 0

        levels.each_with_index do |level_nodes, level_idx|
          current_x = DEFAULT_PADDING
          max_height = 0

          level_nodes.each do |node|
            if node[:type] == :requirement
              req = node[:object]
              dims = calculate_requirement_dimensions(req)

              positioned_requirements[req.name] = {
                requirement: req,
                x: current_x,
                y: current_y,
                width: dims[:width],
                height: dims[:height],
                level: level_idx
              }

              current_x += dims[:width] + DEFAULT_SPACING_X
              max_height = [max_height, dims[:height]].max
            else
              elem = node[:object]
              dims = calculate_element_dimensions(elem)

              positioned_elements[elem.name] = {
                element: elem,
                x: current_x,
                y: current_y,
                width: dims[:width],
                height: dims[:height],
                level: level_idx
              }

              current_x += dims[:width] + DEFAULT_SPACING_X
              max_height = [max_height, dims[:height]].max
            end
          end

          max_width = [max_width, current_x].max
          current_y += max_height + DEFAULT_SPACING_Y
        end

        {
          requirements: positioned_requirements,
          elements: positioned_elements,
          width: max_width + DEFAULT_PADDING,
          height: current_y + DEFAULT_PADDING
        }
      end

      def build_dependency_levels(requirements, elements, relationships)
        # Build a simple level-based layout
        # Level 0: Elements
        # Level 1: Requirements that depend on elements
        # Level 2+: Requirements that depend on other requirements

        nodes_by_name = {}
        requirements.each { |r| nodes_by_name[r.name] = { type: :requirement, object: r, level: nil } }
        elements.each { |e| nodes_by_name[e.name] = { type: :element, object: e, level: nil } }

        # Start with elements at level 0
        elements.each { |e| nodes_by_name[e.name][:level] = 0 }

        # Build dependency map
        dependencies = Hash.new { |h, k| h[k] = [] }
        relationships.each do |rel|
          # Source depends on target (arrow direction)
          dependencies[rel.source] << rel.target
        end

        # Calculate levels for requirements
        changed = true
        max_iterations = 10
        iterations = 0

        while changed && iterations < max_iterations
          changed = false
          iterations += 1

          requirements.each do |req|
            node = nodes_by_name[req.name]
            next if node[:level]

            deps = dependencies[req.name]
            if deps.empty?
              # No dependencies, place at level 1
              node[:level] = 1
              changed = true
            else
              # Check if all dependencies have levels
              dep_levels = deps.map { |d| nodes_by_name[d]&.dig(:level) }.compact
              if dep_levels.size == deps.size
                # All dependencies have levels
                max_dep_level = dep_levels.max || 0
                node[:level] = max_dep_level + 1
                changed = true
              end
            end
          end
        end

        # Assign default level to any remaining nodes
        nodes_by_name.each do |_name, node|
          node[:level] ||= 1 if node[:type] == :requirement
        end

        # Group by level
        levels = []
        nodes_by_name.values.group_by { |n| n[:level] }.sort.each do |_level, nodes|
          levels << nodes
        end

        levels
      end

      def calculate_requirement_dimensions(requirement)
        # Calculate based on text content
        text = requirement.text || ''
        text_lines = text.length > 0 ? ((text.length / 25.0).ceil) : 1

        width = DEFAULT_REQ_WIDTH
        height = DEFAULT_REQ_HEIGHT + (text_lines - 1) * 20

        {
          width: width,
          height: [height, DEFAULT_REQ_HEIGHT].max
        }
      end

      def calculate_element_dimensions(element)
        {
          width: DEFAULT_ELEM_WIDTH,
          height: DEFAULT_ELEM_HEIGHT
        }
      end

      def calculate_relationships(diagram, nodes_layout)
        requirements = nodes_layout[:requirements]
        elements = nodes_layout[:elements]
        all_nodes = requirements.merge(elements)

        diagram.relationships.map do |rel|
          source_node = all_nodes[rel.source]
          target_node = all_nodes[rel.target]

          next unless source_node && target_node

          # Calculate connection points
          source_x = source_node[:x] + source_node[:width] / 2
          source_y = source_node[:y] + source_node[:height]
          target_x = target_node[:x] + target_node[:width] / 2
          target_y = target_node[:y]

          {
            relationship: rel,
            source: rel.source,
            target: rel.target,
            type: rel.type,
            from_x: source_x,
            from_y: source_y,
            to_x: target_x,
            to_y: target_y
          }
        end.compact
      end
    end
  end
end