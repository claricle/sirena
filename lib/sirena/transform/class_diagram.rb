# frozen_string_literal: true

require_relative 'base'
require_relative '../diagram/class_diagram'

module Sirena
  module Transform
    # Class diagram transformer for converting class models to graphs.
    #
    # Converts a typed class diagram model into a generic graph structure
    # suitable for layout computation by elkrb. Handles class box sizing
    # based on attributes and methods, relationship mapping, and hierarchical
    # layout configuration.
    #
    # @example Transform a class diagram
    #   transform = ClassDiagramTransform.new
    #   graph = transform.to_graph(class_diagram)
    class ClassDiagramTransform < Base
      # Default font size for text measurement
      DEFAULT_FONT_SIZE = 14

      # Minimum width for a class box
      MIN_CLASS_WIDTH = 120

      # Height per class compartment line
      LINE_HEIGHT = 20

      # Padding within class box compartments
      COMPARTMENT_PADDING = 10

      # Spacing between classes
      CLASS_SPACING = 80

      # Converts a class diagram to a graph structure.
      #
      # @param diagram [Diagram::ClassDiagram] the class diagram to transform
      # @return [Hash] elkrb-compatible graph hash
      # @raise [TransformError] if diagram is invalid
      def to_graph(diagram)
        raise TransformError, 'Invalid diagram' unless diagram.valid?

        {
          id: diagram.id || 'class_diagram',
          children: transform_entities(diagram),
          edges: transform_relationships(diagram),
          layoutOptions: layout_options(diagram)
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
              stereotype: entity.stereotype,
              attributes: entity.attributes.map { |a| attribute_to_hash(a) },
              methods: entity.class_methods.map { |m| method_to_hash(m) }
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
              source_cardinality: rel.source_cardinality,
              target_cardinality: rel.target_cardinality
            }
          }
        end
      end

      def calculate_entity_dimensions(entity)
        # Calculate width based on longest line (name, attributes, methods)
        max_width = MIN_CLASS_WIDTH

        # Check class name width
        name_text = if entity.stereotype
                      "<<#{entity.stereotype}>>\n#{entity.name}"
                    else
                      entity.name
                    end
        name_width = measure_text(
          name_text,
          font_size: DEFAULT_FONT_SIZE
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

        # Check method widths
        entity.class_methods.each do |method|
          method_text = format_method(method)
          method_width = measure_text(
            method_text,
            font_size: DEFAULT_FONT_SIZE
          )[:width]
          max_width = [max_width, method_width].max
        end

        # Add padding
        total_width = max_width + (COMPARTMENT_PADDING * 2)

        # Calculate height based on compartments
        # Name compartment
        name_lines = entity.stereotype ? 2 : 1
        name_height = name_lines * LINE_HEIGHT

        # Attributes compartment
        attr_height = if entity.attributes.empty?
                        0
                      else
                        (entity.attributes.length * LINE_HEIGHT)
                      end

        # Methods compartment
        method_height = if entity.class_methods.empty?
                          0
                        else
                          (entity.class_methods.length * LINE_HEIGHT)
                        end

        # Total height with compartment separators
        compartment_count = [
          1, # name always present
          entity.attributes.empty? ? 0 : 1,
          entity.class_methods.empty? ? 0 : 1
        ].sum
        separator_height = (compartment_count - 1) * 2 # 2px per separator

        total_height = name_height + attr_height + method_height +
                       separator_height + (COMPARTMENT_PADDING * 2)

        {
          width: total_width,
          height: total_height
        }
      end

      def entity_labels(entity)
        labels = []

        # Main label with class name
        name_text = if entity.stereotype
                      "<<#{entity.stereotype}>>\n#{entity.name}"
                    else
                      entity.name
                    end
        name_dims = measure_text(name_text, font_size: DEFAULT_FONT_SIZE)

        labels << {
          text: name_text,
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

        # Add cardinality labels if present
        if relationship.source_cardinality &&
           !relationship.source_cardinality.empty?
          card_dims = measure_text(
            relationship.source_cardinality,
            font_size: DEFAULT_FONT_SIZE - 2
          )
          labels << {
            text: relationship.source_cardinality,
            width: card_dims[:width],
            height: card_dims[:height],
            position: 'source'
          }
        end

        if relationship.target_cardinality &&
           !relationship.target_cardinality.empty?
          card_dims = measure_text(
            relationship.target_cardinality,
            font_size: DEFAULT_FONT_SIZE - 2
          )
          labels << {
            text: relationship.target_cardinality,
            width: card_dims[:width],
            height: card_dims[:height],
            position: 'target'
          }
        end

        labels
      end

      def format_attribute(attribute)
        parts = [attribute.visibility_symbol, attribute.name]
        parts << ": #{attribute.type}" if attribute.type &&
                                          !attribute.type.empty?
        parts.join(' ')
      end

      def format_method(method)
        parts = [method.visibility_symbol, method.signature]
        parts.join(' ')
      end

      def attribute_to_hash(attribute)
        {
          name: attribute.name,
          type: attribute.type,
          visibility: attribute.visibility
        }
      end

      def method_to_hash(method)
        {
          name: method.name,
          parameters: method.parameters,
          return_type: method.return_type,
          visibility: method.visibility
        }
      end

      def layout_options(diagram)
        # Class diagrams use layered algorithm for UML hierarchy
        # This optimally handles inheritance relationships and class groupings
        # NETWORK_SIMPLEX node placement balances hierarchy with aesthetics
        build_elk_options(
          algorithm: ALGORITHM_LAYERED,
          direction: direction_to_layout(diagram.direction),
          ElkOptions::NODE_NODE_SPACING => CLASS_SPACING,
          ElkOptions::LAYER_SPACING => CLASS_SPACING,
          ElkOptions::EDGE_NODE_SPACING => 40,
          ElkOptions::EDGE_EDGE_SPACING => 20,
          # NETWORK_SIMPLEX for better UML layout with inheritance
          ElkOptions::NODE_PLACEMENT => 'NETWORK_SIMPLEX',
          ElkOptions::MODEL_ORDER => 'NODES_AND_EDGES',
          ElkOptions::HIERARCHY_HANDLING => 'INCLUDE_CHILDREN'
        )
      end

      def direction_to_layout(direction)
        case direction
        when 'TD', 'TB'
          DIRECTION_DOWN
        when 'LR'
          DIRECTION_RIGHT
        when 'RL'
          DIRECTION_LEFT
        when 'BT'
          DIRECTION_UP
        else
          DIRECTION_DOWN # Default for class diagrams is top-down
        end
      end
    end
  end
end
