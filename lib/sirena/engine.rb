# frozen_string_literal: true

module Sirena
  # Orchestrates the complete diagram rendering pipeline.
  #
  # The Engine class coordinates the parse → transform → layout → render
  # pipeline for converting Mermaid source code into SVG output. It handles
  # diagram type detection, retrieves appropriate handlers from the registry,
  # and manages error handling throughout the process.
  #
  # @example Render a flowchart
  #   engine = Sirena::Engine.new
  #   svg = engine.render("graph TD\nA-->B")
  #   puts svg
  #
  # @example Render with options
  #   engine = Sirena::Engine.new
  #   svg = engine.render(source, verbose: true)
  class Engine
    # Error raised when diagram type cannot be detected
    class DiagramTypeError < Error; end

    # Error raised during pipeline execution
    class PipelineError < Error; end

    # Mapping of diagram syntax prefixes to diagram types
    DIAGRAM_TYPE_PATTERNS = {
      flowchart: /\A\s*(graph|flowchart)\s+/i,
      sequence: /\A\s*sequenceDiagram/i,
      class_diagram: /\A\s*classDiagram/i,
      state_diagram: /\A\s*stateDiagram(-v2)?/i,
      er_diagram: /\A\s*erDiagram/i,
      user_journey: /\A\s*journey/i,
      gantt: /\A\s*gantt\s/i,
      pie: /\A\s*pie\s/i,
      timeline: /\A\s*timeline(\s|$)/i,
      quadrant: /\A\s*quadrantChart/i,
      git_graph: /\A\s*gitGraph/i,
      mindmap: /\A\s*mindmap/i,
      kanban: /\A\s*kanban/i,
      radar: /\A\s*radar-beta/i,
      block: /\A\s*block-beta/i,
      requirement: /\A\s*requirementDiagram/i,
      xychart: /\A\s*xychart-beta/i,
      architecture: /\A\s*architecture-beta/i,
      sankey: /\A\s*sankey-beta/i,
      packet: /\A\s*packet-beta/i,
      treemap: /\A\s*treemap(-beta)?/i,
      c4: /\A\s*(C4Context|C4Container|C4Component|C4Dynamic|C4Deployment|C4\s+diagram)/i,
      info: /\A\s*info/i,
      error: /\A\s*(error|Error)/i
    }.freeze

    attr_reader :verbose, :theme

    # Creates a new Engine instance.
    #
    # @param verbose [Boolean] enable verbose output for debugging
    # @param theme [String, Theme, Hash, nil] theme specification
    def initialize(verbose: false, theme: nil)
      @verbose = verbose
      @theme = load_theme(theme)
    end

    # Renders Mermaid source code to SVG.
    #
    # @param mermaid_source [String] Mermaid diagram source code
    # @param options [Hash] rendering options
    # @option options [Boolean] :verbose enable verbose output
    # @option options [String, Theme, Hash, nil] :theme theme override
    # @return [String] SVG XML string
    # @raise [DiagramTypeError] if diagram type cannot be detected
    # @raise [PipelineError] if any pipeline stage fails
    def render(mermaid_source, options = {})
      @verbose = options[:verbose] if options.key?(:verbose)

      # Override theme if specified in options
      theme = options[:theme] ? load_theme(options[:theme]) : @theme

      log 'Starting render pipeline...'

      # Detect diagram type
      diagram_type = detect_diagram_type(mermaid_source)
      log "Detected diagram type: #{diagram_type}"

      # Retrieve handlers
      handlers = retrieve_handlers(diagram_type)
      log "Retrieved handlers for #{diagram_type}"

      # Execute pipeline
      diagram = parse_diagram(mermaid_source, handlers[:parser])
      graph = transform_diagram(diagram, handlers[:transform])
      laid_out_graph = layout_graph(graph)
      svg_document = render_svg(laid_out_graph, handlers[:renderer], theme)

      # Return XML string
      svg_xml = svg_document.to_xml
      log "Render complete, #{svg_xml.length} bytes"

      svg_xml
    rescue DiagramTypeError
      # Re-raise diagram type errors without wrapping
      raise
    rescue StandardError => e
      raise PipelineError,
            "Rendering failed: #{e.message}\n#{e.backtrace.join("\n")}"
    end

    private

    # Detects diagram type from source code syntax.
    #
    # @param source [String] Mermaid source code
    # @return [Symbol] diagram type identifier
    # @raise [DiagramTypeError] if type cannot be detected
    def detect_diagram_type(source)
      DIAGRAM_TYPE_PATTERNS.each do |type, pattern|
        return type if source.match?(pattern)
      end

      raise DiagramTypeError,
            'Unable to detect diagram type from source. ' \
            'Source must start with one of: graph, flowchart, ' \
            'sequenceDiagram, classDiagram, stateDiagram, ' \
            'erDiagram, journey, gantt, or pie'
    end

    # Retrieves handlers for a diagram type.
    #
    # @param type [Symbol] diagram type identifier
    # @return [Hash] hash with :parser, :transform, :renderer keys
    # @raise [DiagramTypeError] if type is not registered
    def retrieve_handlers(type)
      handlers = DiagramRegistry.get(type)

      unless handlers
        raise DiagramTypeError,
              "No handlers registered for diagram type: #{type}"
      end

      handlers
    end

    # Parses source code into diagram model.
    #
    # @param source [String] Mermaid source code
    # @param parser_class [Class] parser class
    # @return [Diagram::Base] parsed diagram model
    def parse_diagram(source, parser_class)
      log 'Parsing diagram...'
      parser = parser_class.new
      diagram = parser.parse(source)
      log "Parse complete: #{diagram.class.name}"
      diagram
    end

    # Transforms diagram model to graph structure.
    #
    # @param diagram [Diagram::Base] diagram model
    # @param transform_class [Class] transform class
    # @return [Object] graph structure
    def transform_diagram(diagram, transform_class)
      log 'Transforming diagram to graph...'
      transform = transform_class.new
      graph = transform.to_graph(diagram)
      log 'Transform complete'
      graph
    end

    # Computes layout for graph.
    #
    # Currently uses a simple fallback layout since elkrb may not be
    # available. In the future, this will attempt to use elkrb for
    # proper graph layout computation.
    #
    # @param graph [Object] graph structure
    # @return [Object] graph with computed positions
    def layout_graph(graph)
      log 'Computing layout...'

      # TODO: Attempt to use elkrb when available
      # For now, use simple fallback positioning
      apply_fallback_layout(graph)

      log 'Layout complete (using fallback positioning)'
      graph
    end

    # Applies simple grid-based fallback layout.
    #
    # This is a placeholder for actual elkrb layout. It arranges
    # nodes in a simple grid pattern. Handles both object-based
    # and hash-based graph structures.
    #
    # @param graph [Object, Hash] graph structure
    # @return [Object, Hash] graph with positions
    def apply_fallback_layout(graph)
      # Handle hash-based graph structure (elkrb-compatible)
      if graph.is_a?(Hash) && graph[:children]
        apply_fallback_layout_to_hash(graph)
      # Handle object-based graph structure
      elsif graph.respond_to?(:nodes)
        nodes = graph.nodes
        nodes.each_with_index do |node, index|
          next unless node.respond_to?(:x=) && node.respond_to?(:y=)

          # Simple grid layout: 3 columns
          col = index % 3
          row = index / 3

          node.x = 50 + (col * 200)
          node.y = 50 + (row * 150)
        end
      end

      graph
    end

    # Applies fallback layout to hash-based graph structure.
    #
    # @param graph [Hash] graph hash with :children
    # @return [Hash] graph with positions added
    def apply_fallback_layout_to_hash(graph)
      children = graph[:children] || []

      # Apply layout to immediate children
      children.each_with_index do |child, index|
        # Skip if already has position
        next if child[:x] && child[:y]

        # Simple grid layout: 3 columns
        col = index % 3
        row = index / 3

        child[:x] = 50 + (col * 250)
        child[:y] = 50 + (row * 200)

        # Recursively apply to nested children
        apply_fallback_layout_to_hash(child) if child[:children]
      end

      graph
    end

    # Renders graph to SVG document.
    #
    # @param graph [Object] laid-out graph
    # @param renderer_class [Class] renderer class
    # @param theme [Theme] theme to use for rendering
    # @return [Svg::Document] SVG document
    def render_svg(graph, renderer_class, theme)
      log 'Rendering to SVG...'
      renderer = renderer_class.new(theme: theme)
      svg = renderer.render(graph)
      log 'SVG render complete'
      svg
    end

    # Loads a theme from various specifications.
    #
    # @param theme_spec [String, Theme, Hash, nil] theme specification
    # @return [Theme] loaded theme
    def load_theme(theme_spec)
      return Theme::Registry.get(:default) if theme_spec.nil?

      case theme_spec
      when String
        # Could be theme name or path to file
        if File.exist?(theme_spec)
          Theme.load(theme_spec)
        else
          Theme::Registry.get(theme_spec.to_sym) ||
            Theme::Registry.get(:default)
        end
      when Theme
        theme_spec
      when Hash
        Theme.new(**theme_spec)
      else
        Theme::Registry.get(:default)
      end
    end

    # Logs a message if verbose mode is enabled.
    #
    # @param message [String] message to log
    # @return [void]
    def log(message)
      puts "[Sirena::Engine] #{message}" if verbose
    end
  end
end
