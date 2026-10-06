# frozen_string_literal: true

require "spec_helper"
require "rexml/document"

RSpec.describe "Flowchart Integration" do
  describe "complete flowchart pipeline" do
    let(:parser) { Sirena::Parser::Flowchart.new }
    let(:transform) { Sirena::Layout::Flowchart.new }
    let(:renderer) { Sirena::Renderer::Flowchart.new }

    it "parses, transforms, and renders a simple flowchart" do
      source = "graph TD\nA[Start]-->B[End]"

      # Parse
      diagram = parser.parse(source)
      expect(diagram).to be_a(Sirena::Diagram::Flowchart)
      expect(diagram.valid?).to be true

      # Transform
      graph = transform.to_graph(diagram)
      expect(graph).to be_a(Hash)
      expect(graph[:children].length).to eq(2)
      expect(graph[:edges].length).to eq(1)

      # Render (without elkrb layout, just with graph structure)
      svg = renderer.render(graph)
      expect(svg).to be_a(Sirena::Svg::Document)
      expect(svg.children).not_to be_empty
    end

    it "handles multiple node shapes" do
      source = <<~MERMAID
        graph TD
        A[Rectangle]
        B(Rounded)
        C{Rhombus}
        A-->B-->C
      MERMAID

      diagram = parser.parse(source)

      expect(diagram.nodes.length).to eq(3)
      expect(diagram.find_node("A").shape).to eq("rect")
      expect(diagram.find_node("B").shape).to eq("rounded")
      expect(diagram.find_node("C").shape).to eq("rhombus")

      graph = transform.to_graph(diagram)
      svg = renderer.render(graph)

      expect(svg).to be_a(Sirena::Svg::Document)
    end

    it "handles different directions" do
      source = "graph LR\nA-->B"

      diagram = parser.parse(source)
      expect(diagram.direction).to eq("LR")

      graph = transform.to_graph(diagram)
      expect(graph[:layoutOptions]["elk.direction"]).to eq("RIGHT")
    end
  end

  describe "DiagramRegistry integration" do
    it "has flowchart registered" do
      expect(Sirena::DiagramRegistry.registered?(:flowchart)).to be true
    end

    it "retrieves flowchart handlers" do
      handlers = Sirena::DiagramRegistry.get(:flowchart)

      expect(handlers).not_to be_nil
      expect(handlers[:parser]).to eq(
        Sirena::Parser::Flowchart,
      )
      expect(handlers[:transform]).to eq(
        Sirena::Layout::Flowchart,
      )
      expect(handlers[:renderer]).to eq(
        Sirena::Renderer::Flowchart,
      )
    end
  end

  describe "an empty flowchart" do
    corpus_dir = File.expand_path("../mermaid/flowchart", __dir__)

    empty_sources = {
      "147 (declare a class)" =>
        File.read("#{corpus_dir}/147_parser_should_be_possible_to_declare_a_class_142.mmd"),
      "148 (declare multiple classes)" =>
        File.read("#{corpus_dir}/148_parser_should_be_possible_to_declare_multiple_classes_143.mmd"),
      "149 (declare a class with a dot in the style)" =>
        File.read("#{corpus_dir}/149_parser_should_be_possible_to_declare_a_class_with_a_dot_in_the_style_144.mmd"),
      "150 (declare a class with a space in the style)" =>
        File.read("#{corpus_dir}/150_parser_should_be_possible_to_declare_a_class_with_a_space_in_the_style_145.mmd"),
      "a bare header" => "graph TD\n",
      "a header with only a comment" => "flowchart LR\n%% just a comment\n",
      "class without a matching classDef" => "graph TD\nclass A foo\n",
    }.freeze

    # `create_document`'s own padding (`Renderer::Base#create_document`, 20
    # per side) is the only contributor once `calculate_width`/
    # `calculate_height` return 0 for a graph with nothing drawn -- see
    # `Renderer::Flowchart`.
    empty_canvas_attributes = { "width" => "40.0", "height" => "40.0", "viewBox" => "0 0 40 40" }.freeze

    empty_sources.each do |description, source|
      context "with #{description}" do
        let(:svg) { Sirena::Engine.new.render(source) }
        let(:root) { REXML::Document.new(svg).root }

        # One example per property, not one big example: each gets its
        # own failure rather than the first assertion hiding the rest.
        empty_canvas_attributes.each do |attribute, expected|
          it "sets the #{attribute} attribute to #{expected.inspect}" do
            expect(root.attributes[attribute]).to eq(expected)
          end
        end

        it "is a well-formed svg document" do
          expect(root.name).to eq("svg")
        end

        it "draws no child elements" do
          expect(root.elements.to_a).to be_empty
        end
      end
    end

    # Passes before and after this change -- keep it: it is the only
    # end-to-end check that a declared-but-empty subgraph still raises
    # LayoutError instead of silently rendering mermaid's fallback node,
    # which this model has no way to draw.
    it "still refuses a subgraph declared with no members" do
      source = "flowchart TD\nsubgraph s\nend\n"

      expect { Sirena::Engine.new.render(source) }.to raise_error(Sirena::Layout::LayoutError)
    end
  end
end
