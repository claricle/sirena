# frozen_string_literal: true

module Sirena
  module Transform
    # Abstract base class for diagram transformers.
    #
    # Transformers convert typed diagram models into generic graph structures
    # suitable for layout computation by elkrb. Each diagram type has its own
    # transformer that maps diagram-specific elements to graph nodes and edges.
    #
    # The transformer is also responsible for calculating node dimensions
    # using TextMeasurement and setting appropriate layout options.
    #
    # @example Define a custom transformer
    #   class FlowchartTransform < Transform::Base
    #     def to_graph(diagram)
    #       graph = create_graph
    #       # Add nodes and edges based on diagram structure
    #       graph
    #     end
    #   end
    #
    # @abstract Subclass and implement #to_graph
    class Base
      # ELK layout algorithms supported (matching mermaid-js)
      # @see https://www.eclipse.org/elk/reference/algorithms.html
      ALGORITHM_LAYERED = 'layered'
      ALGORITHM_STRESS = 'stress'
      ALGORITHM_FORCE = 'force'
      ALGORITHM_MRTREE = 'mrtree'
      ALGORITHM_SPORE_OVERLAP = 'sporeOverlap'

      # ELK layout directions
      DIRECTION_DOWN = 'DOWN'
      DIRECTION_UP = 'UP'
      DIRECTION_LEFT = 'LEFT'
      DIRECTION_RIGHT = 'RIGHT'

      # Default spacing values (in pixels)
      DEFAULT_NODE_SPACING = 50
      DEFAULT_EDGE_SPACING = 30
      DEFAULT_LAYER_SPACING = 50

      # ELK option keys for consistent configuration
      # @see https://www.eclipse.org/elk/reference/options.html
      module ElkOptions
        ALGORITHM = 'algorithm'
        DIRECTION = 'elk.direction'

        # Spacing options
        NODE_NODE_SPACING = 'elk.spacing.nodeNode'
        EDGE_NODE_SPACING = 'elk.spacing.edgeNode'
        EDGE_EDGE_SPACING = 'elk.spacing.edgeEdge'
        LAYER_SPACING = 'elk.layered.spacing.nodeNodeBetweenLayers'

        # Layered algorithm options
        NODE_PLACEMENT = 'elk.layered.nodePlacement.strategy'
        CROSSING_MINIMIZATION =
          'elk.layered.crossingMinimization.strategy'
        MODEL_ORDER = 'elk.layered.considerModelOrder.strategy'
        COMPACTION = 'elk.layered.compaction.postCompaction.strategy'

        # Hierarchy and grouping
        HIERARCHY_HANDLING = 'elk.hierarchyHandling'

        # Edge routing
        EDGE_ROUTING = 'elk.edgeRouting'
      end

      # Converts a diagram model to an elkrb graph structure.
      #
      # This method should be overridden by subclasses to implement
      # diagram-specific graph conversion logic.
      #
      # @param diagram [Diagram::Base] the diagram model to convert
      # @return [Object] elkrb graph object with nodes and edges
      # @raise [NotImplementedError] if not implemented by subclass
      def to_graph(diagram)
        raise NotImplementedError,
              "#{self.class} must implement #to_graph(diagram)"
      end

      protected

      # Measures text dimensions for node sizing.
      #
      # @param text [String] the text to measure
      # @param font_size [Numeric] the font size in points
      # @param width [Numeric, nil] optional width override
      # @param height [Numeric, nil] optional height override
      # @return [Hash] hash with :width and :height keys
      def measure_text(text, font_size:, width: nil, height: nil)
        TextMeasurement.measure(text,
                                font_size: font_size,
                                width: width,
                                height: height)
      end

      # Creates ELK layout options with proper configuration.
      #
      # This method provides sensible defaults based on mermaid-js patterns
      # and can be overridden by subclasses for diagram-specific needs.
      #
      # @param algorithm [String] ELK algorithm to use
      # @param direction [String] layout direction
      # @param options [Hash] additional ELK options to merge
      # @return [Hash] complete ELK layout options
      def build_elk_options(algorithm: ALGORITHM_LAYERED,
                           direction: DIRECTION_DOWN,
                           **options)
        base_options = {
          ElkOptions::ALGORITHM => algorithm,
          ElkOptions::DIRECTION => direction
        }

        # Add algorithm-specific defaults
        case algorithm
        when ALGORITHM_LAYERED
          base_options.merge!(layered_algorithm_options)
        when ALGORITHM_STRESS, ALGORITHM_FORCE
          base_options.merge!(force_based_algorithm_options)
        end

        base_options.merge(options)
      end

      # Default layout options for layered algorithm.
      #
      # The layered algorithm is optimal for hierarchical diagrams like
      # flowcharts, sequence diagrams, and class diagrams. It minimizes
      # edge crossings and places nodes in distinct layers.
      #
      # @return [Hash] layered algorithm options
      def layered_algorithm_options
        {
          # Node and edge spacing
          ElkOptions::NODE_NODE_SPACING => DEFAULT_NODE_SPACING,
          ElkOptions::EDGE_NODE_SPACING => DEFAULT_EDGE_SPACING,
          ElkOptions::EDGE_EDGE_SPACING => DEFAULT_EDGE_SPACING,
          ElkOptions::LAYER_SPACING => DEFAULT_LAYER_SPACING,

          # Use SIMPLE node placement for predictable layouts
          ElkOptions::NODE_PLACEMENT => 'SIMPLE',

          # Consider model order for consistent positioning
          ElkOptions::MODEL_ORDER => 'NODES_AND_EDGES'
        }
      end

      # Default layout options for force-based algorithms.
      #
      # Force-based algorithms (stress, force) are optimal for graphs
      # without clear hierarchy, like ER diagrams or network diagrams.
      #
      # @return [Hash] force-based algorithm options
      def force_based_algorithm_options
        {
          ElkOptions::NODE_NODE_SPACING => DEFAULT_NODE_SPACING * 1.5,
          ElkOptions::EDGE_NODE_SPACING => DEFAULT_EDGE_SPACING,
          ElkOptions::EDGE_EDGE_SPACING => DEFAULT_EDGE_SPACING
        }
      end

      # Calculates node padding based on content type.
      #
      # @param node_type [Symbol] the type of node
      # @return [Hash] padding hash with :top, :bottom, :left, :right
      def node_padding(node_type)
        case node_type
        when :rect
          { top: 10, bottom: 10, left: 15, right: 15 }
        when :circle
          { top: 15, bottom: 15, left: 15, right: 15 }
        when :diamond
          { top: 20, bottom: 20, left: 20, right: 20 }
        else
          { top: 10, bottom: 10, left: 10, right: 10 }
        end
      end

      # Calculates total node dimensions including padding.
      #
      # @param content_width [Numeric] width of node content
      # @param content_height [Numeric] height of node content
      # @param node_type [Symbol] the type of node
      # @return [Hash] dimensions hash with :width and :height
      def calculate_node_dimensions(content_width, content_height, node_type)
        padding = node_padding(node_type)
        {
          width: content_width + padding[:left] + padding[:right],
          height: content_height + padding[:top] + padding[:bottom]
        }
      end
    end

    # Error raised during transformation.
    class TransformError < StandardError; end
  end
end
