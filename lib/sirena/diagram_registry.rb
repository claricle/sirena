# frozen_string_literal: true

module Sirena
  # Registry for diagram type handlers.
  #
  # This class implements the registry pattern to manage diagram type
  # handlers without hardcoding type checks. Each diagram type registers
  # its parser, transform, and renderer components, which can be retrieved
  # dynamically during diagram processing.
  #
  # @example Registering a diagram type
  #   DiagramRegistry.register(
  #     :flowchart,
  #     parser: Parser::FlowchartGrammar,
  #     transform: Transform::FlowchartTransform,
  #     renderer: Renderer::FlowchartRenderer
  #   )
  #
  # @example Retrieving handlers for a type
  #   handlers = DiagramRegistry.get(:flowchart)
  #   # => { parser: Parser::FlowchartGrammar,
  #   #      transform: Transform::FlowchartTransform,
  #   #      renderer: Renderer::FlowchartRenderer }
  #
  # @example Listing registered types
  #   DiagramRegistry.types
  #   # => [:flowchart, :sequence, :class_diagram]
  class DiagramRegistry
    @handlers = {}

    class << self
      # Registers handlers for a diagram type.
      #
      # @param type [Symbol] the diagram type identifier
      # @param parser [Class] the parser class for this diagram type
      # @param transform [Class] the transform class for this diagram type
      # @param renderer [Class] the renderer class for this diagram type
      # @return [Hash] the registered handler hash
      #
      # @example Register a new diagram type
      #   DiagramRegistry.register(
      #     :flowchart,
      #     parser: Parser::FlowchartGrammar,
      #     transform: Transform::FlowchartTransform,
      #     renderer: Renderer::FlowchartRenderer
      #   )
      def register(type, parser:, transform:, renderer:)
        @handlers[type] = {
          parser: parser,
          transform: transform,
          renderer: renderer
        }
      end

      # Retrieves handlers for a diagram type.
      #
      # @param type [Symbol] the diagram type identifier
      # @return [Hash, nil] hash with :parser, :transform, and :renderer
      #   keys, or nil if type not registered
      #
      # @example Get handlers for a type
      #   handlers = DiagramRegistry.get(:flowchart)
      #   parser_class = handlers[:parser]
      def get(type)
        @handlers[type]
      end

      # Returns all registered diagram types.
      #
      # @return [Array<Symbol>] list of registered diagram type identifiers
      #
      # @example List all types
      #   DiagramRegistry.types
      #   # => [:flowchart, :sequence, :class_diagram]
      def types
        @handlers.keys
      end

      # Checks if a diagram type is registered.
      #
      # @param type [Symbol] the diagram type identifier
      # @return [Boolean] true if type is registered
      #
      # @example Check if type is registered
      #   DiagramRegistry.registered?(:flowchart)
      #   # => true
      def registered?(type)
        @handlers.key?(type)
      end

      # Clears all registered handlers.
      #
      # This method is primarily useful for testing purposes.
      #
      # @return [Hash] empty handler hash
      def clear
        @handlers = {}
      end
    end
  end
end
