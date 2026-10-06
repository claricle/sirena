# frozen_string_literal: true

require_relative "../source"
require_relative "../error/diagram_type_error"
require_relative "../error/pipeline_error"
require_relative "parsed"

module Sirena
  module Notation
    # The Mermaid notation: detects which of its diagram types a source is,
    # applies the preamble rules, and parses it into a diagram model.
    #
    # A diagram type needs three entries: a DIAGRAM_TYPE_PATTERNS regex (what
    # detection reads), a DIAGRAM_TYPE_KEYWORDS word (what the error message
    # prints) and its handlers via `register_type` (parser, transform, renderer
    # and model). `register_type` alone does not make a type detectable.
    module Mermaid
      extend self

      # Mapping of diagram syntax prefixes to diagram types.
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
      DIAGRAM_TYPE_PATTERNS = {
        flowchart: /\A\s*(?:flowchart-elk|(?i:graph|flowchart))([\s<>^]|\z)/,
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
        c4: /\A\s*(C4Context|C4Container|C4Component|C4Dynamic|C4Deployment|
          C4\s+diagram)/ix,
        info: /\A\s*info/i,
        error: /\A\s*(error|Error)/i,
      }.freeze

      # The keyword a source actually needs to start with, for the "must
      # start with one of" error message -- DIAGRAM_TYPE_PATTERNS's own keys
      # (`:sequence`, `:class_diagram`, ...) are internal type names, not what
      # a user types (`sequenceDiagram`, `classDiagram`). Keep it keyed the
      # same as DIAGRAM_TYPE_PATTERNS: a type missing here prints its internal
      # name in that message, and engine_spec fails when the key sets differ.
      DIAGRAM_TYPE_KEYWORDS = {
        flowchart: "graph, flowchart, or flowchart-elk",
        sequence: "sequenceDiagram",
        class_diagram: "classDiagram",
        state_diagram: "stateDiagram or stateDiagram-v2",
        er_diagram: "erDiagram",
        user_journey: "journey",
        gantt: "gantt",
        pie: "pie",
        timeline: "timeline",
        quadrant: "quadrantChart",
        git_graph: "gitGraph",
        mindmap: "mindmap",
        kanban: "kanban",
        radar: "radar-beta",
        block: "block-beta",
        requirement: "requirementDiagram",
        xychart: "xychart-beta",
        architecture: "architecture-beta",
        sankey: "sankey-beta",
        packet: "packet-beta",
        treemap: "treemap or treemap-beta",
        c4: "C4Context, C4Container, C4Component, C4Dynamic, C4Deployment, " \
            "or a C4 diagram",
        info: "info",
        error: "error",
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
        comment: ["an empty comment", REFUSES_BARE_COMMENT],
        directive: ["a directive with no header", REFUSES_HEADERLESS_DIRECTIVE],
        frontmatter: [
          "frontmatter behind another item",
          REFUSES_LATE_FRONTMATTER,
        ],
      }.freeze
      private_constant :REFUSED_PREAMBLE

      # @return [Symbol]
      def id
        :mermaid
      end

      # Registers the handlers of one diagram type.
      def register_type(type, parser:, transform:, renderer:, model:)
        type_table[type] = {
          parser: parser,
          transform: transform,
          renderer: renderer,
          model: model,
        }
      end

      # @return [Hash, nil] handlers for a type, nil when not registered
      def type_handlers(type)
        type_table[type]
      end

      # @return [Array<Symbol>] registered types in registration order
      def types
        type_table.keys
      end

      def type_registered?(type)
        type_table.key?(type)
      end

      def clear_types
        type_table.clear
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
        handlers = handlers_for(type, logger)
        diagram = parse_diagram(handlers, preamble[:body], title, logger)
        Parsed.new(type: type, diagram: diagram,
                   transform: handlers[:transform],
                   renderer: handlers[:renderer])
      end

      # @return [Symbol] the first type whose pattern matches the body
      def detect_type(source)
        DIAGRAM_TYPE_PATTERNS.each do |type, pattern|
          return type if source.match?(pattern)
        end

        raise Engine::DiagramTypeError,
              "Unable to detect diagram type from source. " \
              "Source must start with one of: #{registered_type_names}"
      end

      private

      def handlers_for(type, logger)
        handlers = type_handlers(type)
        unless handlers
          raise Engine::DiagramTypeError,
                "No handlers registered for diagram type: #{type}"
        end

        logger&.debug("Retrieved handlers for #{type}")
        handlers
      end

      def parse_diagram(handlers, body, title, logger)
        logger&.debug("Parsing diagram...")
        diagram = handlers[:parser].new.parse(body)
        logger&.debug("Parse complete: #{diagram.class.name}")
        diagram.title = title if title && diagram.title.nil?
        diagram
      end

      def type_table
        @type_table ||= {}
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
