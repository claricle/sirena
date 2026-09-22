# frozen_string_literal: true

require_relative 'error/diagram_type_error'
require_relative 'error/pipeline_error'

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
    # Mapping of diagram syntax prefixes to diagram types.
    #
    # A direction glyph needs no gap after the flowchart keyword. mmdc
    # draws `graph>`, `graph<` and `graph^`, and the grammar takes them.
    # Detection used to demand whitespace, so those headers died here
    # with DiagramTypeError before the parser saw the line.
    DIAGRAM_TYPE_PATTERNS = {
      flowchart: /\A\s*(graph|flowchart)([\s<>^]|\z)/i,
      sequence: /\A\s*sequenceDiagram/i,
      class_diagram: /\A\s*classDiagram/i,
      state_diagram: /\A\s*stateDiagram(-v2)?/i,
      er_diagram: /\A\s*erDiagram/i,
      user_journey: /\A\s*journey/i,
      gantt: /\A\s*gantt(\s|\z)/i,
      pie: /\A\s*pie(\s|\z)/i,
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

    # An empty preamble item — a bare `%%`, or a `%%{...}%%` with no
    # directive header — is not universally invalid. Every type was probed
    # with both, and these eight refuse both.
    REFUSES_BARE_COMMENT = [
      :flowchart, :er_diagram, :user_journey, :gantt, :timeline, :block,
      :sankey, :requirement
    ].freeze
    private_constant :REFUSES_BARE_COMMENT

    # stateDiagram is the odd one out: it draws a bare `%%` and refuses a
    # directive with no header.
    REFUSES_HEADERLESS_DIRECTIVE = (
      REFUSES_BARE_COMMENT + [:state_diagram]
    ).freeze
    private_constant :REFUSES_HEADERLESS_DIRECTIVE

    # A fence that is not the first thing in the file is not frontmatter
    # to mermaid. It stays in the text, and the diagram's own parser meets
    # it: these seventeen stop on it, and pie, gitGraph, radar,
    # architecture, packet and info skip the lines and draw the diagram.
    REFUSES_LATE_FRONTMATTER = [
      :flowchart, :sequence, :class_diagram, :state_diagram, :er_diagram,
      :user_journey, :gantt, :timeline, :quadrant, :mindmap, :kanban,
      :block, :requirement, :xychart, :sankey, :treemap, :c4
    ].freeze
    private_constant :REFUSES_LATE_FRONTMATTER

    # What each preamble item mermaid cannot make sense of costs, and how
    # to say so.
    REFUSED_PREAMBLE = {
      comment: ['an empty comment', REFUSES_BARE_COMMENT],
      directive: ['a directive with no header', REFUSES_HEADERLESS_DIRECTIVE],
      frontmatter: ['frontmatter behind another item', REFUSES_LATE_FRONTMATTER]
    }.freeze
    private_constant :REFUSED_PREAMBLE

    attr_reader :verbose, :theme

    # Creates a new Engine instance.
    #
    # @param verbose [Boolean] enable verbose output for debugging
    # @param theme [String, Theme, Hash, nil] theme specification
    # @param today [Date, nil] reference date for diagrams that need one
    #   (gantt). Pin it to make rendering reproducible; nil uses the real
    #   date.
    def initialize(verbose: false, theme: nil, today: nil)
      @verbose = verbose
      @theme = load_theme(theme)
      @today = today
    rescue *EXHAUSTION_ERRORS => e
      # Theme loading parses attacker-supplied YAML, and it happens HERE --
      # before `render` is ever called, so `render`'s own rescue cannot see
      # it. A host embedding sirena and catching `StandardError` still loses
      # its whole process, because neither exhaustion class is one.
      #
      # Reproduce with a theme whose YAML nests 2000 deep:
      #   Sirena::Engine.new(theme: bomb_path)   # raised raw SystemStackError
      raise PipelineError, "Theme loading failed: #{e.message}"
    end

    # Renders Mermaid source code to SVG.
    #
    # @param mermaid_source [String] Mermaid diagram source code
    # @param options [Hash] rendering options
    # @option options [Boolean] :verbose enable verbose output
    # @option options [String, Theme, Hash, nil] :theme theme override
    # @option options [Date, nil] :today reference date override
    # @return [String] SVG XML string
    # @raise [DiagramTypeError] if diagram type cannot be detected
    # @raise [Parser::ParseError] if the source fails to parse
    # @raise [Transform::TransformError] if the diagram fails its own
    #   validity check
    # @raise [Renderer::RenderError] if rendering itself fails
    # @raise [PipelineError] if a stage fails with no error class of its own
    def render(mermaid_source, options = {})
      @verbose = options[:verbose] if options.key?(:verbose)

      # Override theme if specified in options
      theme = options[:theme] ? load_theme(options[:theme]) : @theme

      # Same for the reference date. Without this, Sirena.render and the
      # rake tasks that call it get the wall clock no matter what they pass,
      # silently — examples:generate rewrote its committed gantt SVG daily.
      today = options.key?(:today) ? options[:today] : @today

      log 'Starting render pipeline...'

      # Mermaid allows frontmatter, %%{init}%% directives and %% comments
      # before the diagram keyword; detection and parsing both need the body.
      preamble = Source.split(mermaid_source)

      # Read the title now, not lazily: frontmatter is validated whether or
      # not the body supplies its own title, so `title: [` is refused even
      # when the diagram has a title of its own.
      frontmatter_title = Source.title(preamble[:frontmatter])

      # Detect diagram type
      diagram_type = detect_diagram_type(preamble[:body])
      log "Detected diagram type: #{diagram_type}"

      reject_degenerate_preamble(diagram_type, preamble[:degenerate])

      # Retrieve handlers
      handlers = retrieve_handlers(diagram_type)
      log "Retrieved handlers for #{diagram_type}"

      # Execute pipeline
      diagram = parse_diagram(preamble[:body], handlers[:parser])
      apply_frontmatter_title(diagram, frontmatter_title)
      graph = transform_diagram(diagram, handlers[:transform], today)
      laid_out_graph = layout_graph(graph)
      svg_document = render_svg(laid_out_graph, handlers[:renderer], theme)

      # Return XML string
      svg_xml = svg_document.to_xml
      log "Render complete, #{svg_xml.length} bytes"

      svg_xml
    rescue Error
      # Every layer raises its own Sirena::Error subclass (DiagramTypeError,
      # Parser::ParseError, Transform::TransformError, Renderer::RenderError)
      # naming the stage that failed. Wrapping one into PipelineError would
      # erase exactly the field the corpus harness records as `stage`, so
      # let it propagate unwrapped instead.
      raise
    rescue *EXHAUSTION_ERRORS => e
      # `EXHAUSTION_ERRORS` are not `StandardError`, so without naming them
      # here a deeply nested document takes the whole host down instead of
      # failing one render.
      #
      # The message carries `e.message` only, never `e.backtrace`. A real
      # stack overflow's backtrace runs to thousands of frames -- measured
      # at 1,044,280 bytes for one bomb through an unguarded type -- and
      # embedding that here meant every failure in a batch kept a
      # megabyte-sized string alive in `BatchCommand`'s error list: the
      # very structure meant to survive exhaustion re-accumulating it.
      # Raising inside the rescue that caught `e` chains it onto
      # `PipelineError` as `cause` automatically, so `e` and its backtrace
      # are still one `.cause` away for anyone debugging; they are just
      # not baked into the string every caller of `#message` receives.
      raise PipelineError, "Rendering failed: #{e.message}"
    rescue StandardError => e
      # A failure with no layer error of its own. `e` becomes `cause`
      # automatically because we are still inside the rescue; never
      # stringify a backtrace into the message.
      raise PipelineError, "Rendering failed: #{e.class}: #{e.message}"
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

    # Whether an odd preamble item is an error belongs to the diagram
    # type, not to the split — the split runs first, and it cannot know.
    # Refusing them for everyone rejected fifteen types' worth of sources
    # that mmdc renders.
    def reject_degenerate_preamble(diagram_type, degenerate)
      kind = degenerate.find do |item|
        REFUSED_PREAMBLE.fetch(item).last.include?(diagram_type)
      end
      return unless kind

      raise PipelineError,
            "A #{diagram_type} diagram does not accept " \
            "#{REFUSED_PREAMBLE.fetch(kind).first}."
    end

    # Applies a frontmatter title, unless the body already set one.
    #
    # Ten grammars parse their own inline `title` line. The frontmatter
    # title is a default beneath those, not an override.
    #
    # @param diagram [Diagram::Base] the parsed diagram
    # @param title [String, nil] the title the frontmatter set
    # @return [void]
    def apply_frontmatter_title(diagram, title)
      diagram.title = title if title && diagram.title.nil?
    end

    # Retrieves handlers for a diagram type.
    #
    # @param type [Symbol] diagram type identifier
    # @return [Hash] hash with :parser, :transform, :renderer, :model keys
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
    # @param today [Date, nil] reference date, or nil for the real date
    # @return [Hash] graph structure
    def transform_diagram(diagram, transform_class, today)
      log 'Transforming diagram to graph...'
      transform = transform_class.new
      # Every registered transform inherits Transform::Base and so has
      # today=; the respond_to? guard is defensive, not load-bearing.
      transform.today = today if today && transform.respond_to?(:today=)
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
    # @param graph [Hash] graph structure
    # @return [Hash] graph with computed positions
    def layout_graph(graph)
      log 'Computing layout...'

      # TODO: Attempt to use elkrb when available
      # For now, use simple fallback positioning
      Layout::Fallback.apply(graph)

      log 'Layout complete (using fallback positioning)'
      graph
    end

    # Renders graph to SVG document.
    #
    # @param graph [Hash] laid-out graph
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
