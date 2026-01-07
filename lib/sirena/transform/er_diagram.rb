# frozen_string_literal: true

require_relative 'base'
require_relative '../diagram/er_diagram'

module Sirena
  module Transform
    # ER diagram transformer for converting ER models to graphs.
    #
    # Converts a typed ER diagram model into a generic graph structure
    # suitable for layout computation by elkrb. Handles entity box sizing
    # based on entity name and attribute count, relationship mapping with
    # cardinality, and layered layout configuration.
    #
    # @example Transform an ER diagram
    #   transform = ErDiagramTransform.new
    #   graph = transform.to_graph(er_diagram)
    class ErDiagramTransform < Base
      # Default font size for text measurement
      DEFAULT_FONT_SIZE = 14

      # Minimum width for an entity box
      MIN_ENTITY_WIDTH = 150

      # Height per entity line (name + attributes)
      LINE_HEIGHT = 20

      # Padding within entity box
      ENTITY_PADDING = 10

      # Spacing between entities
      ENTITY_SPACING = 100

      # Converts an ER diagram to a graph structure.
      #
      # @param diagram [Diagram::ErDiagram] the ER diagram to transform
      # @return [Hash] elkrb-compatible graph hash
      # @raise [TransformError] if diagram is invalid
      def to_graph(diagram)
        raise TransformError, 'Invalid diagram' unless diagram.valid?

        {
          id: diagram.id || 'er_diagram',
          children: transform_entities(diagram),
          edges: transform_relationships(diagram),
          layoutOptions: layout_options
        }
      end

      private

      def transform_entities(diagram)
        diagram.entities.map do |entity|
          dims = calculate_entity_dimensions(entity)

          {
            id: entity.id,
            width: dims[:width],
            height: dims[:height],
            labels: entity_labels(entity),
            metadata: {
              name: entity.name,
              attributes: entity.attributes.map { |a| attribute_to_hash(a) }
            }
          }
        end
      end

      def transform_relationships(diagram)
        return [] if diagram.relationships.nil? ||
                     diagram.relationships.empty?

        diagram.relationships.map do |rel|
          {
            id: "#{rel.from_id}_to_#{rel.to_id}",
            sources: [rel.from_id],
            targets: [rel.to_id],
            labels: relationship_labels(rel),
            metadata: {
              relationship_type: rel.relationship_type,
              cardinality_from: rel.cardinality_from,
              cardinality_to: rel.cardinality_to
            }
          }
        end
      end

      def calculate_entity_dimensions(entity)
        # Calculate width based on entity name and attributes
        max_width = MIN_ENTITY_WIDTH

        # Check entity name width
        name_width = measure_text(
          entity.name,
          font_size: DEFAULT_FONT_SIZE + 2
        )[:width]
        max_width = [max_width, name_width].max

        # Check attribute widths
        entity.attributes.each do |attr|
          attr_text = format_attribute(attr)
          attr_width = measure_text(
            attr_text,
            font_size: DEFAULT_FONT_SIZE
          )[:width]
          max_width = [max_width, attr_width].max
        end

        # Add padding
        total_width = max_width + (ENTITY_PADDING * 2)

        # Calculate height: entity name + attributes
        line_count = 1 + entity.attributes.length
        total_height = (line_count * LINE_HEIGHT) + (ENTITY_PADDING * 2)

        {
          width: total_width,
          height: total_height
        }
      end

      def entity_labels(entity)
        labels = []

        # Main label with entity name
        name_dims = measure_text(
          entity.name,
          font_size: DEFAULT_FONT_SIZE + 2
        )

        labels << {
          text: entity.name,
          width: name_dims[:width],
          height: name_dims[:height]
        }

        labels
      end

      def relationship_labels(relationship)
        labels = []

        # Add relationship label if present
        if relationship.label && !relationship.label.empty?
          label_dims = measure_text(
            relationship.label,
            font_size: DEFAULT_FONT_SIZE
          )
          labels << {
            text: relationship.label,
            width: label_dims[:width],
            height: label_dims[:height]
          }
        end

        labels
      end

      def format_attribute(attribute)
        parts = []

        # Add key type marker if present
        parts << attribute.key_type if attribute.key_type &&
                                       !attribute.key_type.empty?

        # Add attribute name
        parts << attribute.name

        # Add type if present
        parts << attribute.attribute_type if attribute.attribute_type &&
                                             !attribute.attribute_type.empty?

        parts.join(' ')
      end

      def attribute_to_hash(attribute)
        {
          name: attribute.name,
          attribute_type: attribute.attribute_type,
          key_type: attribute.key_type
        }
      end

      def layout_options
        # ER diagrams use layered algorithm for hierarchical entity layout
        # DIRECTION_RIGHT provides left-to-right flow for entity relationships
        # NETWORK_SIMPLEX placement optimizes entity box positioning while
        # respecting relationship cardinality and foreign key constraints
        build_elk_options(
          algorithm: ALGORITHM_LAYERED,
          direction: DIRECTION_RIGHT,
          ElkOptions::NODE_NODE_SPACING => ENTITY_SPACING,
          ElkOptions::LAYER_SPACING => ENTITY_SPACING,
          ElkOptions::EDGE_NODE_SPACING => 50,
          ElkOptions::EDGE_EDGE_SPACING => 30,
          # NETWORK_SIMPLEX for better entity relationship layout
          ElkOptions::NODE_PLACEMENT => 'NETWORK_SIMPLEX',
          ElkOptions::MODEL_ORDER => 'NODES_AND_EDGES',
          ElkOptions::HIERARCHY_HANDLING => 'INCLUDE_CHILDREN'
        )
      end
    end
  end
end
