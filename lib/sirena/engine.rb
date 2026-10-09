# frozen_string_literal: true

require "logger"

require_relative "error/diagram_type_error"
require_relative "error/pipeline_error"
require_relative "notation"
require_relative "notation/mermaid"

module Sirena
  # Orchestrates the complete diagram rendering pipeline.
  #
  # The Engine class coordinates the parse → transform → layout → render
  # pipeline for converting diagram source code into SVG output. Choosing the
  # notation belongs to {Notation.resolve}, and detection and parsing to the
  # notation itself (see {Notation::Mermaid}); the engine runs what the
  # notation returns and manages error handling throughout the process.
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
    # @deprecated Use {Sirena::Notation::Mermaid::DIAGRAM_TYPE_PATTERNS}.
    DIAGRAM_TYPE_PATTERNS = Notation::Mermaid::DIAGRAM_TYPE_PATTERNS

    # @deprecated Use {Sirena::Notation::Mermaid::DIAGRAM_TYPE_KEYWORDS}.
    DIAGRAM_TYPE_KEYWORDS = Notation::Mermaid::DIAGRAM_TYPE_KEYWORDS

    attr_reader :verbose, :theme, :logger

    # Creates a new Engine instance.
    #
    # @param verbose [Boolean] enable verbose output for debugging
    # @param theme [String, Symbol, Theme, Hash, nil] theme specification
    # @param today [Date, nil] reference date for diagrams that need one
    #   (gantt). Pin it to make rendering reproducible; nil uses the real
    #   date.
    # @param notation [Symbol, String, nil] the notation to read sources
    #   with; nil lets each render pick one from its path and source
    # @param logger [Logger, nil] destination for diagnostics. A host
    #   embedding Sirena and reading stdout as pure SVG cannot tolerate log
    #   lines landing on the same stream, so the default logs to $stderr
    #   instead; pass one in to redirect or format diagnostics your own way.
    # @raise [PipelineError] if `notation` is invalid or not registered
    def initialize(verbose: false, theme: nil, today: nil, logger: nil,
                   notation: nil)
      @verbose = verbose
      @notation_id = registered_id(notation)
      @theme = load_theme(theme)
      @today = today
      @logger = logger || Logger.new($stderr).tap do |default_logger|
        default_logger.formatter = proc do |_severity, _time, _progname, message|
          "[Sirena::Engine] #{message}\n"
        end
      end
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

    # Renders diagram source code to SVG.
    #
    # @param source [String] diagram source code
    # @param options [Hash] rendering options
    # @option options [Boolean] :verbose enable verbose output
    # @option options [String, Symbol, Theme, Hash, nil] :theme theme override
    # @option options [Date, nil] :today reference date override
    # @option options [Symbol, String, nil] :notation notation override
    # @option options [String, nil] :path where the source came from; its
    #   extension picks the notation when none is given
    # @return [String] SVG XML string
    # @raise [PipelineError] if `notation` is invalid or not registered
    # @raise [DiagramTypeError] if diagram type cannot be detected
    # @raise [Parser::ParseError] if the source fails to parse
    # @raise [Layout::LayoutError] if the diagram fails its own
    #   validity check
    # @raise [Renderer::RenderError] if rendering itself fails
    # @raise [PipelineError] if a stage fails with no error class of its own
    def render(source, options = {})
      @verbose = options[:verbose] if options.key?(:verbose)

      # Override theme if specified in options
      theme = options[:theme] ? load_theme(options[:theme]) : @theme

      # Same for the reference date. Without this, Sirena.render and the
      # rake tasks that call it get the wall clock no matter what they pass,
      # silently — examples:generate rewrote its committed gantt SVG daily.
      today = options.key?(:today) ? options[:today] : @today

      log "Starting render pipeline..."

      explicit_notation = case options[:notation]
                          when nil then @notation_id
                          else options[:notation]
                          end
      notation = Notation.resolve(
        explicit: explicit_notation,
        path: options[:path],
        source: source,
      )
      parsed = parse_source(notation, source)

      graph = transform_diagram(parsed.diagram, parsed.transform, today, theme)
      laid_out_graph = layout_graph(graph)
      svg_document = render_svg(laid_out_graph, parsed.renderer, theme)

      # Return XML string
      svg_xml = svg_document.to_xml
      log "Render complete, #{svg_xml.length} bytes"

      svg_xml
    rescue Error
      # Every layer raises its own Sirena::Error subclass (DiagramTypeError,
      # Parser::ParseError, Layout::LayoutError, Renderer::RenderError)
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
    rescue Notation::PluginFailure => e
      # A failure with no layer error of its own, from a notation or the
      # layers it returned: any Exception, not only a StandardError, but
      # never exit, a signal or a host's timeout. `e` becomes `cause`
      # automatically because we are still inside the rescue; never
      # stringify a backtrace into the message.
      raise PipelineError, "Rendering failed: #{describe_failure(e)}"
    end

    private

    # "Class: message", for an exception whose own #message may raise (an
    # RSpec::Expectations::MultipleExpectationsNotMetError built without its
    # aggregator does).
    def describe_failure(error)
      "#{error.class}: #{error.message}"
    rescue Notation::PluginFailure
      "#{error.class}: <message unavailable>"
    end

    # A notation that wants the engine's progress lines declares a `logger:`
    # keyword; one that does not is called with the source alone.
    def parse_source(notation, source)
      if accepts_logger?(notation)
        notation.parse(source, logger: verbose ? logger : nil)
      else
        notation.parse(source)
      end
    end

    # The registry's key for a validated notation, not the id the plugin
    # answers later.
    def registered_id(notation)
      case notation
      when nil
        nil
      else
        Notation.fetch(notation)
        case notation
        when Symbol then notation
        when String then String.instance_method(:to_sym).bind_call(notation)
        end
      end
    end

    def accepts_logger?(notation)
      notation.method(:parse).parameters.any? do |kind, name|
        kind == :key && name == :logger
      end
    end

    # Lays out the diagram model.
    #
    # @param diagram [Diagram::Base] diagram model
    # @param transform_class [Class] layout class
    # @param today [Date, nil] reference date, or nil for the real date
    # @param theme [Theme] theme the layout may size text with
    # @return [Layout::Scene, Layout::Legacy] a Scene, or a wrapped graph
    def transform_diagram(diagram, transform_class, today, theme)
      log "Transforming diagram to graph..."
      result = transform_class.new.call(diagram, theme: theme, today: today)
      log "Transform complete"
      result
    end

    # Computes layout for the layout result.
    #
    # Only a legacy graph goes through Layout::Grid, which is temporary;
    # see its header. A Scene is already positioned and Grid must not
    # touch it. Unwrap before Grid, and hand the renderer the graph.
    #
    # @param result [Layout::Scene, Layout::Legacy] layout result
    # @return [Layout::Scene, Hash] what the renderer takes
    def layout_graph(result)
      log "Computing layout..."
      return result unless result.is_a?(Layout::Legacy)

      graph = Layout::Grid.apply(result.payload)

      log "Layout complete (using fallback positioning)"
      graph
    end

    # Renders graph to SVG document.
    #
    # @param graph [Layout::Scene, Hash] laid-out graph, as #layout_graph
    #   returns it -- a Scene for a converted layout, a Hash otherwise
    # @param renderer_class [Class] renderer class
    # @param theme [Theme] theme to use for rendering
    # @return [Svg::Document] SVG document
    def render_svg(graph, renderer_class, theme)
      log "Rendering to SVG..."
      renderer = renderer_class.new(theme: theme)
      svg = renderer.render(graph)
      log "SVG render complete"
      svg
    end

    # Loads a theme from various specifications.
    #
    # @param theme_spec [String, Symbol, Theme, Hash, nil] theme specification
    # @return [Theme] loaded theme
    def load_theme(theme_spec)
      return Theme::Registry.get(:default) if theme_spec.nil?

      case theme_spec
      when String
        # Could be theme name or path to file
        if File.exist?(theme_spec)
          Theme.load(theme_spec)
        else
          resolve_theme_name(theme_spec)
        end
      when Symbol
        # Theme::Registry is itself keyed by Symbol internally, so a Symbol
        # here is a plausible caller mistake (e.g. `theme: :dark`), not an
        # exotic input -- it must go through the same raise-on-unknown path
        # as a String, not the silent-default `else` below.
        resolve_theme_name(theme_spec.to_s)
      when Theme
        theme_spec
      when Hash
        Theme.new(**theme_spec)
      else
        Theme::Registry.get(:default)
      end
    end

    # Resolves a theme name against the registry, or raises -- an unknown
    # name used to fall back to the default theme silently (exit 0, wrong
    # theme drawn). A typo and an intentional `--theme default` looked
    # identical to the caller.
    #
    # @param name [String] the requested theme name
    # @return [Theme] the matching registered theme
    # @raise [PipelineError] if no theme is registered under that name
    def resolve_theme_name(name)
      Theme::Registry.get(name.to_sym) || raise(
        PipelineError,
        "Unknown theme: #{name}. Valid themes: " \
        "#{Theme::Registry.list.map(&:to_s).sort.join(', ')}",
      )
    end

    # Logs a diagnostic message at debug level, gated on @verbose. This
    # never touches the logger's own `.level` -- an injected logger may be
    # shared with (or owned by) the host embedding Sirena, and mutating its
    # level as a side effect of construction/render either corrupts the
    # host's own filtering or crashes outright for a duck-typed logger that
    # doesn't implement `level=` (only `debug`/`info`/`warn`, the documented
    # contract). A plain guard needs neither.
    #
    # @param message [String] message to log
    # @return [void]
    def log(message)
      logger.debug(message) if verbose
    end
  end
end
