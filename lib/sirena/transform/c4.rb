# frozen_string_literal: true

require_relative 'base'
require_relative '../diagram/c4'

module Sirena
  module Transform
    # C4 transformer for converting C4 models to graphs.
    #
    # Converts a typed C4 diagram model into a generic graph structure
    # suitable for layout computation by elkrb. Handles element positioning,
    # boundary grouping, and relationship routing.
    #
    # @example Transform a C4 diagram
    #   transform = C4Transform.new
    #   graph = transform.to_graph(c4_diagram)
    class C4Transform < Base
      # Default font size for text measurement
      DEFAULT_FONT_SIZE = 14

      # Element dimensions based on type
      PERSON_WIDTH = 140
      PERSON_HEIGHT = 180
      SYSTEM_WIDTH = 160
      SYSTEM_HEIGHT = 120
      CONTAINER_WIDTH = 160
      CONTAINER_HEIGHT = 120
      COMPONENT_WIDTH = 160
      COMPONENT_HEIGHT = 100

      # Spacing
      ELEMENT_SPACING = 60
      BOUNDARY_PADDING = 40
      LEVEL_SPACING = 80

      # Converts a C4 diagram to a graph structure.
      #
      # @param diagram [Diagram::C4] the C4 diagram to transform
      # @return [Hash] elkrb-compatible graph hash
      # @raise [TransformError] if diagram is invalid
      def to_graph(diagram)
        raise TransformError, 'Invalid diagram' unless diagram.valid?

        # Build hierarchy with boundaries as containers
        root_elements = diagram.elements.select { |e| e.boundary_id.nil? }
        root_boundaries = diagram.boundaries.select { |b| b.parent_id.nil? }

        {
          id: diagram.id || 'c4',
          children: transform_root_nodes(diagram, root_elements,
                                         root_boundaries),
          edges: transform_relationships(diagram),
          layoutOptions: layout_options(diagram),
          metadata: {
            level: diagram.level,
            title: diagram.title,
            element_count: diagram.elements.length,
            relationship_count: diagram.relationships.length
          }
        }
      end

      private

      def transform_root_nodes(diagram, elements, boundaries)
        nodes = []

        # Add root-level boundaries (which contain their own elements)
        boundaries.each do |boundary|
          nodes << transform_boundary(diagram, boundary)
        end

        # Add root-level elements (not in any boundary)
        elements.each do |element|
          nodes << transform_element(element)
        end

        nodes
      end

      def transform_boundary(diagram, boundary)
        # Get elements in this boundary
        elements = diagram.elements_in_boundary(boundary.id)
        child_boundaries = diagram.boundaries_in_boundary(boundary.id)

        children = []

        # Add child boundaries first
        child_boundaries.each do |child_boundary|
          children << transform_boundary(diagram, child_boundary)
        end

        # Add elements in this boundary
        elements.each do |element|
          children << transform_element(element)
        end

        # Calculate boundary dimensions based on contents
        dims = calculate_boundary_dimensions(children)

        {
          id: boundary.id,
          width: dims[:width],
          height: dims[:height],
          labels: [
            {
              text: boundary.label,
              width: measure_text(boundary.label,
                                  font_size: DEFAULT_FONT_SIZE + 2)[:width],
              height: measure_text(boundary.label,
                                   font_size: DEFAULT_FONT_SIZE + 2)[:height]
            }
          ],
          children: children,
          layoutOptions: boundary_layout_options,
          metadata: {
            boundary_type: boundary.boundary_type,
            type_param: boundary.type_param,
            link: boundary.link,
            tags: boundary.tags
          }
        }
      end

      def transform_element(element)
        dims = element_dimensions(element)

        labels = []

        # Main label
        label_dims = measure_text(element.label,
                                   font_size: DEFAULT_FONT_SIZE + 2)
        labels << {
          text: element.label,
          width: label_dims[:width],
          height: label_dims[:height]
        }

        # Description (if present)
        if element.description && !element.description.empty?
          desc_dims = measure_text(element.description,
                                    font_size: DEFAULT_FONT_SIZE - 2)
          labels << {
            text: element.description,
            width: desc_dims[:width],
            height: desc_dims[:height]
          }
        end

        # Technology (if present)
        if element.technology && !element.technology.empty?
          tech_dims = measure_text(element.technology,
                                    font_size: DEFAULT_FONT_SIZE - 2)
          labels << {
            text: "[#{element.technology}]",
            width: tech_dims[:width],
            height: tech_dims[:height]
          }
        end

        {
          id: element.id,
          width: dims[:width],
          height: dims[:height],
          labels: labels,
          metadata: {
            element_type: element.element_type,
            base_type: element.base_type,
            external: element.external,
            sprite: element.sprite,
            link: element.link,
            tags: element.tags,
            person: element.person?,
            system: element.system?,
            container: element.container?,
            component: element.component?
          }
        }
      end

      def transform_relationships(diagram)
        return [] if diagram.relationships.nil? || diagram.relationships.empty?

        diagram.relationships.map.with_index do |rel, index|
          labels = []

          if rel.label && !rel.label.empty?
            label_dims = measure_text(rel.label, font_size: DEFAULT_FONT_SIZE)
            labels << {
              text: rel.label,
              width: label_dims[:width],
              height: label_dims[:height]
            }
          end

          if rel.technology && !rel.technology.empty?
            tech_dims = measure_text("[#{rel.technology}]",
                                      font_size: DEFAULT_FONT_SIZE - 2)
            labels << {
              text: "[#{rel.technology}]",
              width: tech_dims[:width],
              height: tech_dims[:height]
            }
          end

          {
            id: "rel_#{index}",
            sources: [rel.from_id],
            targets: [rel.to_id],
            labels: labels,
            metadata: {
              rel_type: rel.rel_type,
              bidirectional: rel.bidirectional?
            }
          }
        end
      end

      def element_dimensions(element)
        # Base dimensions on element type
        if element.person?
          { width: PERSON_WIDTH, height: PERSON_HEIGHT }
        elsif element.system?
          { width: SYSTEM_WIDTH, height: SYSTEM_HEIGHT }
        elsif element.container?
          { width: CONTAINER_WIDTH, height: CONTAINER_HEIGHT }
        elsif element.component?
          { width: COMPONENT_WIDTH, height: COMPONENT_HEIGHT }
        else
          { width: SYSTEM_WIDTH, height: SYSTEM_HEIGHT }
        end
      end

      def calculate_boundary_dimensions(children)
        return { width: 300, height: 200 } if children.empty?

        # Calculate based on child count and type
        # Simple heuristic: arrange in grid
        count = children.length
        cols = Math.sqrt(count).ceil
        rows = (count.to_f / cols).ceil

        max_width = children.map { |c| c[:width] || 160 }.max
        max_height = children.map { |c| c[:height] || 120 }.max

        width = (cols * max_width) + ((cols + 1) * ELEMENT_SPACING) +
                (2 * BOUNDARY_PADDING)
        height = (rows * max_height) + ((rows + 1) * ELEMENT_SPACING) +
                 (2 * BOUNDARY_PADDING) + 30 # Extra for title

        { width: [width, 300].max, height: [height, 200].max }
      end

      def layout_options(diagram)
        # C4 diagrams use hierarchical layout
        # Top-down for Context/Container, can be left-right for Component
        direction = case diagram.level
                    when 'Component', 'Code'
                      DIRECTION_RIGHT
                    else
                      DIRECTION_DOWN
                    end

        build_elk_options(
          algorithm: ALGORITHM_LAYERED,
          direction: direction,
          ElkOptions::NODE_NODE_SPACING => ELEMENT_SPACING,
          ElkOptions::LAYER_SPACING => LEVEL_SPACING,
          ElkOptions::EDGE_NODE_SPACING => 25,
          ElkOptions::EDGE_EDGE_SPACING => 20,
          ElkOptions::HIERARCHY_HANDLING => 'INCLUDE_CHILDREN',
          ElkOptions::NODE_PLACEMENT => 'NETWORK_SIMPLEX'
        )
      end

      def boundary_layout_options
        # Boundaries use box packing for internal layout
        {
          'elk.algorithm' => 'box',
          'elk.box.packingMode' => 'GROUP_MIXED',
          'elk.padding' => "[top=#{BOUNDARY_PADDING},left=#{BOUNDARY_PADDING}," \
                          "bottom=#{BOUNDARY_PADDING},right=#{BOUNDARY_PADDING}]",
          'elk.spacing.nodeNode' => ELEMENT_SPACING.to_s
        }
      end
    end
  end
end