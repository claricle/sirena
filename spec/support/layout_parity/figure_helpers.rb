# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # Shared helpers for the extractor specs: fixture access and the few
    # shapes of result they compare.
    module FigureHelpers
      SPEC_ROOT = File.expand_path("../..", __dir__)

      def extract(svg, recognizer)
        SvgFigureExtractor.new(recognizer).extract(svg)
      end

      def figure_of(file, recognizer)
        path = File.join(SPEC_ROOT, "fixtures", "layout_parity", file)
        extract(File.read(path), recognizer)
      end

      def box_of(figure, key)
        element = figure.elements.find { |e| e.key == key }
        element.bbox.to_a.map { |n| n.round(6) }
      end

      def parents_of(figure)
        figure.elements.to_h { |e| [e.key, e.parent] }
      end

      # An mmdc reference SVG, by path under spec/fixtures_mermaid.
      def reference_svg(path)
        File.read(File.join(SPEC_ROOT, "fixtures_mermaid", path))
      end

      # A mermaid-js corpus source, by path under spec/mermaid.
      def corpus_source(path)
        File.read(File.join(SPEC_ROOT, "mermaid", path))
      end

      def skewed_svg
        <<~SVG
          <svg viewBox="0 0 9 9">
            <g class="node" id="flowchart-a-0" transform="skewX(5)">
              <rect width="1" height="1"/>
            </g>
          </svg>
        SVG
      end

      def nested_subgraphs_source
        <<~MERMAID
          flowchart TD
            subgraph B
              c
            end
            a-->c
            subgraph A
              b-->B
              a
            end
        MERMAID
      end

      # [mmdc reference, Sirena render] of one flowchart corpus case.
      def flowchart_sides(name)
        [reference_svg("flowchart/#{name}.svg"),
         Sirena.render(corpus_source("flowchart/#{name}.mmd"))]
      end

      # [mmdc reference, Sirena render] of a two-participant sequence.
      def sequence_sides
        [reference_svg("sequence/001_platform_knsv_0.svg"),
         Sirena.render("sequenceDiagram\n  Alice->>Bob: Hi\n")]
      end

      def participant_tops(svg, recognizer)
        keys = extract(svg, recognizer).keys
        keys.select { |key| key[0] == :"participant-top" }.sort_by(&:last)
      end

      def expected_tops
        [[:"participant-top", nil, "Alice"], [:"participant-top", nil, "Bob"]]
      end

      def nested_subgraph_parents
        { "A" => nil, "B" => "A", "a" => "A", "b" => "A", "c" => "B" }
      end
    end
  end
end
