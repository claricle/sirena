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

    # Mermaid deletes directives and then comments before it looks for a
    # diagram keyword, so neither is part of the header. Detection here read
    # the source as written, so `%%{init: ...}%%` on the first line reached
    # no pattern and the source died with DiagramTypeError before the parser
    # -- which already reads both constructs -- ever saw it.
    #
    # This is mermaid 11.16.1's own pattern, transcribed rather than
    # reinvented. It ships at
    # `dist/chunks/mermaid.core/chunk-I66GZJ75.mjs:4990` and is applied by
    # `removeDirectives` (`chunk-NSK5VX7P.mjs:123-125`) and again by
    # `detectType` (`chunk-I66GZJ75.mjs:5006-5008`). Transcribing buys the
    # awkward part: the closing `}%%` is OPTIONAL, so an unterminated
    # directive swallows the rest of the document and the header with it.
    # `%%{init: {'theme':'dark'}` above a sequenceDiagram is
    # UnknownDiagramError to mmdc, and a per-line strip would have drawn it.
    #
    # JavaScript's four capture groups are dropped; nothing reads them.
    #
    # Applied ONCE, where mermaid applies it twice (`removeDirectives`, then
    # `detectType` again over the result). Measured across 62,002 inputs --
    # the 1,997 corpus cases and a 60,005-case fuzz -- the two disagree on a
    # single input, a doubled `%%{%%{` opener that mmdc refuses and this
    # draws. Nothing in the corpus reaches it, and a second pass here would
    # not be faithful either: mermaid runs a differently-anchored comment
    # strip between its two.
    DIRECTIVE = /
      %{2}\{\s*
      (?:\w+\s*:|\w+)\s*
      (?:\w+|(?:(?!\}%{2}).|\r?\n)*)?\s*
      (?:\}%{2})?
    /xi

    # `anyCommentRegex`, `chunk-I66GZJ75.mjs:4991`.
    COMMENT = /\s*%%.*\n/

    # `cleanupText`, `mermaid.core.mjs:1000-1005`, runs first in
    # `preprocessDiagram` (:1030-1042) -- so every regex after it sees LF
    # only. Skipping it is not cosmetic: Ruby's `.` excludes just `\n`,
    # where JavaScript's also excludes `\r`, and the two disagree in BOTH
    # directions on a bare CR. `"%% a\rb\nsequenceDiagram"` is nil to mmdc
    # and was :sequence without this line; `"%% note\rsequenceDiagram"` is
    # :sequence to mmdc and was nil. A 30,005-case fuzz missed both, because
    # its alphabet emitted CRLF and never a lone CR.
    LINE_FEEDS = /\r\n?/

    private_constant :DIRECTIVE, :COMMENT, :LINE_FEEDS

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
    # @raise [PipelineError] if any pipeline stage fails
    def render(mermaid_source, options = {})
      @verbose = options[:verbose] if options.key?(:verbose)

      # Override theme if specified in options
      theme = options[:theme] ? load_theme(options[:theme]) : @theme

      # Same for the reference date. Without this, Sirena.render and the
      # rake tasks that call it get the wall clock no matter what they pass,
      # silently — examples:generate rewrote its committed gantt SVG daily.
      today = options.key?(:today) ? options[:today] : @today

      log 'Starting render pipeline...'

      # Detect diagram type
      diagram_type = detect_diagram_type(mermaid_source)
      log "Detected diagram type: #{diagram_type}"

      # Retrieve handlers
      handlers = retrieve_handlers(diagram_type)
      log "Retrieved handlers for #{diagram_type}"

      # Execute pipeline
      diagram = parse_diagram(mermaid_source, handlers[:parser])
      graph = transform_diagram(diagram, handlers[:transform], today)
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
      detectable = detectable_source(source)

      DIAGRAM_TYPE_PATTERNS.each do |type, pattern|
        return type if detectable.match?(pattern)
      end

      raise DiagramTypeError,
            'Unable to detect diagram type from source. ' \
            'Source must start with one of: graph, flowchart, ' \
            'sequenceDiagram, classDiagram, stateDiagram, ' \
            'erDiagram, journey, gantt, or pie'
    end

    # The source as mermaid's detector sees it. Only detection uses this:
    # the parser is handed the source as written, because every grammar
    # already carries a `comment` rule and these cases parse clean once
    # they get past this method.
    #
    # Frontmatter is the one thing `preprocessDiagram` strips that this
    # does not, and it is left out on purpose rather than by oversight.
    # Measured over all 1,997 corpus cases: stripping it detects exactly
    # one more (`unknown/079_platform_yari2_78.mmd` -> er_diagram) and that
    # case then dies in the parser, which has no frontmatter rule --
    # `Failed to match sequence (WS? HEADER WS? STATEMENTS? WS?) at line 1
    # char 1`. Frontmatter also carries a title and a config that change
    # the picture, so reading it is a diagram feature rather than a
    # detection fix, and half of one buys a worse error and no drawing.
    #
    # @param source [String] Mermaid source code
    # @return [String] source as mermaid's detector reads it
    def detectable_source(source)
      source.gsub(LINE_FEEDS, "\n").gsub(DIRECTIVE, '').gsub(COMMENT, "\n")
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
    # @param today [Date, nil] reference date, or nil for the real date
    # @return [Hash] graph structure
    def transform_diagram(diagram, transform_class, today)
      log 'Transforming diagram to graph...'
      transform = transform_class.new
      # Only Transform::Base subclasses consume a reference date. Seven
      # transforms (git_graph, kanban, mindmap, packet, radar, treemap,
      # xy_chart) stand outside that hierarchy and read no clock at all, so
      # pinning them is meaningless — sending today= to them just crashed.
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
