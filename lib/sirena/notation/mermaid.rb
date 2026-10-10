# frozen_string_literal: true

require_relative "../source"
require_relative "../error/diagram_type_error"
require_relative "../error/pipeline_error"
require_relative "parsed"
require_relative "mermaid/ir_adapter"

module Sirena
  module Notation
    # The Mermaid notation: detects which of its diagram types a source is,
    # applies the preamble rules, and parses it into a diagram model.
    #
    # A diagram type is one row of {TYPES}: the regex detection reads and the
    # word the error message prints. Its parser, layout, renderer and model
    # are the classes named after the type in {Parser}, {Layout}, {Renderer}
    # and {Diagram} (`:pie` is `Parser::Pie`, ...); a row whose class name is
    # not the camelised type carries it as `name:` (`:xychart` -> `XyChart`).
    module Mermaid
      extend self

      # Every Mermaid diagram type, in detection order. The keyword is what a
      # source actually starts with, for the "must start with one of" message:
      # the type name (`:sequence`) is not what a user types.
      #
      # A direction glyph needs no gap after the flowchart keyword. mmdc
      # draws `graph>`, `graph<` and `graph^`, and the grammar takes them.
      # Detection used to demand whitespace, so those headers died here
      # with DiagramTypeError before the parser saw the line.
      #
      # The `-elk` suffix is deliberately excluded from the outer `/i`: mmdc's
      # own detector (`/^\s*flowchart-elk/`, no `i` flag) only recognises the
      # lowercase spelling, while its bare `flowchart`/`graph` detector is
      # also case-sensitive but Sirena already treats those case-insensitively
      # (pre-existing, unrelated to this suffix). Matching the outer `/i` to
      # `-elk` too let `flowchart-ELK` reach detection as a flowchart, then
      # fail in the grammar (which only defines lowercase `flowchart-elk`)
      # with ParseError instead of the DiagramTypeError an unsupported header
      # should raise.
      TYPES = {
        flowchart: {
          pattern: /\A\s*(?:flowchart-elk|(?i:graph|flowchart))([\s<>^]|\z)/,
          keyword: "graph, flowchart, or flowchart-elk",
        },
        sequence: {
          pattern: /\A\s*sequenceDiagram/i,
          keyword: "sequenceDiagram",
        },
        class_diagram: {
          pattern: /\A\s*classDiagram/i,
          keyword: "classDiagram",
        },
        state_diagram: {
          pattern: /\A\s*stateDiagram(-v2)?/i,
          keyword: "stateDiagram or stateDiagram-v2",
        },
        er_diagram: {
          pattern: /\A\s*erDiagram/i,
          keyword: "erDiagram",
        },
        user_journey: {
          pattern: /\A\s*journey/i,
          keyword: "journey",
        },
        gantt: {
          pattern: /\A\s*gantt(\s|\z)/i,
          keyword: "gantt",
        },
        pie: {
          pattern: /\A\s*pie(\s|\z)/i,
          keyword: "pie",
        },
        timeline: {
          pattern: /\A\s*timeline(\s|$)/i,
          keyword: "timeline",
        },
        quadrant: {
          pattern: /\A\s*quadrantChart/i,
          keyword: "quadrantChart",
        },
        git_graph: {
          pattern: /\A\s*gitGraph/i,
          keyword: "gitGraph",
        },
        mindmap: {
          pattern: /\A\s*mindmap/i,
          keyword: "mindmap",
        },
        kanban: {
          pattern: /\A\s*kanban/i,
          keyword: "kanban",
        },
        radar: {
          pattern: /\A\s*radar-beta/i,
          keyword: "radar-beta",
        },
        block: {
          pattern: /\A\s*block-beta/i,
          keyword: "block-beta",
        },
        requirement: {
          pattern: /\A\s*requirementDiagram/i,
          keyword: "requirementDiagram",
        },
        xychart: {
          pattern: /\A\s*xychart-beta/i,
          keyword: "xychart-beta",
          name: "XyChart",
        },
        architecture: {
          pattern: /\A\s*architecture-beta/i,
          keyword: "architecture-beta",
        },
        sankey: {
          pattern: /\A\s*sankey-beta/i,
          keyword: "sankey-beta",
        },
        packet: {
          pattern: /\A\s*packet-beta/i,
          keyword: "packet-beta",
        },
        treemap: {
          pattern: /\A\s*treemap(-beta)?/i,
          keyword: "treemap or treemap-beta",
        },
        c4: {
          pattern: /\A\s*(C4Context|C4Container|C4Component|C4Dynamic|
            C4Deployment|C4\s+diagram)/ix,
          keyword: "C4Context, C4Container, C4Component, C4Dynamic, " \
                   "C4Deployment, or a C4 diagram",
        },
        info: {
          pattern: /\A\s*info/i,
          keyword: "info",
        },
        error: {
          pattern: /\A\s*(error|Error)/i,
          keyword: "error",
        },
      }.freeze

      # @deprecated Read {TYPES}; kept because specs and callers use these.
      DIAGRAM_TYPE_PATTERNS =
        TYPES.transform_values { |row| row[:pattern] }.freeze

      # @deprecated Read {TYPES}.
      DIAGRAM_TYPE_KEYWORDS =
        TYPES.transform_values { |row| row[:keyword] }.freeze

      # An empty preamble item — a bare `%%`, or a `%%{...}%%` with no
      # directive header — is not universally invalid. Every type was probed
      # with both, and these eight refuse both.
      REFUSES_BARE_COMMENT = %i[
        flowchart er_diagram user_journey gantt timeline block
        sankey requirement
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
      REFUSES_LATE_FRONTMATTER = %i[
        flowchart sequence class_diagram state_diagram er_diagram
        user_journey gantt timeline quadrant mindmap kanban
        block requirement xychart sankey treemap c4
      ].freeze
      private_constant :REFUSES_LATE_FRONTMATTER

      # What each preamble item mermaid cannot make sense of costs, and how
      # to say so.
      REFUSED_PREAMBLE = {
        comment: ["an empty comment", REFUSES_BARE_COMMENT],
        directive: ["a directive with no header", REFUSES_HEADERLESS_DIRECTIVE],
        frontmatter: [
          "frontmatter behind another item",
          REFUSES_LATE_FRONTMATTER,
        ],
      }.freeze
      private_constant :REFUSED_PREAMBLE

      EXTENSIONS = [".mmd"].freeze
      private_constant :EXTENSIONS

      # @return [Symbol]
      def id
        :mermaid
      end

      # @return [Array<String>] file extensions this notation reads
      def extensions
        EXTENSIONS
      end

      # Whether the source, past its preamble, opens with a Mermaid type
      # keyword. `Source.split` accepts any String, binary and invalid UTF-8
      # included.
      #
      # @param source [String]
      # @return [Boolean]
      def claims?(source)
        !matching_type(Source.split(source)[:body]).nil?
      end

      # @return [Hash, nil] the classes serving a type, nil when not in
      #   {TYPES}
      def type_handlers(type)
        return unless type_registered?(type)

        {
          parser: layer_class(Parser, type, Parser::ParseError),
          transform: layer_class(Layout, type, Layout::LayoutError),
          renderer: layer_class(Renderer, type, Renderer::RenderError),
          model: layer_class(Diagram, type, Parser::ParseError),
        }
      end

      # @return [Array<Symbol>] the diagram types, in detection order
      def types
        TYPES.keys
      end

      def type_registered?(type)
        TYPES.key?(type)
      end

      # The class a layer module holds for a type, by naming convention.
      #
      # @param layer [Module] Parser, Layout, Renderer or Diagram
      # @param error [Class] raised when the class does not exist, so a broken
      #   lookup fails as that layer and never as a bare NameError
      # @raise [Engine::DiagramTypeError] when the type is not in {TYPES}
      def layer_class(layer, type, error)
        row = TYPES.fetch(type) do
          raise Engine::DiagramTypeError, "Unknown diagram type: #{type}"
        end
        name = row[:name] || type.to_s.split("_").map(&:capitalize).join
        return layer.const_get(name, false) if layer.const_defined?(name, false)

        raise error, "No #{layer}::#{name} class for diagram type: #{type}"
      end

      # Parses Mermaid source into a {Parsed}.
      #
      # @param source [String] Mermaid source
      # @param logger [#debug, nil] receives the progress lines the engine
      #   prints under `verbose`
      # @raise [Engine::DiagramTypeError] when the source is not Mermaid or
      #   its type has no handlers
      # @raise [Engine::PipelineError] when the preamble is degenerate
      def parse(source, logger: nil)
        preamble = Source.split(source)
        title = Source.title(preamble[:frontmatter])
        type = detect_type(preamble[:body])
        logger&.debug("Detected diagram type: #{type}")
        reject_degenerate_preamble(type, preamble[:degenerate])
        diagram = parse_diagram(type, preamble[:body], title, logger)
        diagram = IRAdapter.call(type, diagram)
        Parsed.new(type: type, diagram: diagram,
                   transform: layer_class(Layout, type, Layout::LayoutError),
                   renderer: layer_class(Renderer, type, Renderer::RenderError))
      end

      # @return [Symbol] the first type whose pattern matches the body
      def detect_type(source)
        type = matching_type(source)
        return type if type

        raise Engine::DiagramTypeError,
              "Unable to detect diagram type from source. " \
              "Source must start with one of: #{registered_type_names}"
      end

      private

      def matching_type(body)
        TYPES.each do |type, row|
          return type if body.match?(row[:pattern])
        end
        nil
      end

      def parse_diagram(type, body, title, logger)
        logger&.debug("Retrieved handlers for #{type}")
        logger&.debug("Parsing diagram...")
        diagram = Parser.for(type).parse(body)
        logger&.debug("Parse complete: #{diagram.class.name}")
        diagram.title = title if title && diagram.title.nil?
        diagram
      end

      def registered_type_names
        types.sort.map { |type| DIAGRAM_TYPE_KEYWORDS.fetch(type, type.to_s) }
          .join(", ")
      end

      def reject_degenerate_preamble(diagram_type, degenerate)
        kind = degenerate.find do |item|
          REFUSED_PREAMBLE.fetch(item).last.include?(diagram_type)
        end
        return unless kind

        raise Engine::PipelineError,
              "A #{diagram_type} diagram does not accept " \
              "#{REFUSED_PREAMBLE.fetch(kind).first}."
      end
    end
  end
end
