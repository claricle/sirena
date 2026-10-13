# frozen_string_literal: true

require "spec_helper"
require "rexml/document"

RSpec.describe Sirena::Parser::Flowchart, :aggregate_failures do
  describe "complete flowchart pipeline" do
    let(:diagram) { described_class.new.parse(source) }
    let(:scene) { Sirena::Layout::Flowchart.new.to_graph(diagram) }
    let(:svg) { Sirena::Renderer::Flowchart.new.render(scene) }

    context "with a simple flowchart" do
      let(:source) { "graph TD\nA[Start]-->B[End]" }

      it "parses a valid Flowchart" do
        expect(diagram).to be_a(Sirena::Diagram::Flowchart)
        expect(diagram.valid?).to be true
      end

      it "transforms to a Scene with both nodes and the edge" do
        expect(scene).to be_a(Sirena::Layout::Flowchart::Scene)
        expect(scene.children.length).to eq(2)
        expect(scene.edges.length).to eq(1)
      end

      it "renders a non-empty SVG document" do
        expect(svg).to be_a(Sirena::Svg::Document)
        expect(svg.children).not_to be_empty
      end
    end

    context "with multiple node shapes" do
      let(:source) do
        <<~MERMAID
          graph TD
          A[Rectangle]
          B(Rounded)
          C{Rhombus}
          A-->B-->C
        MERMAID
      end

      it "parses every node" do
        expect(diagram.nodes.length).to eq(3)
      end

      it "parses each node's shape" do
        expect(diagram.find_node("A").shape).to eq("rect")
        expect(diagram.find_node("B").shape).to eq("rounded")
        expect(diagram.find_node("C").shape).to eq("rhombus")
      end

      it "renders an SVG document" do
        expect(svg).to be_a(Sirena::Svg::Document)
      end
    end

    context "with a left-to-right self loop" do
      let(:source) { "graph LR\nA-->A" }

      it "parses the direction" do
        expect(diagram.direction).to eq("LR")
      end

      it "bends the loop to the right of the node" do
        node = scene.children.first
        bends = scene.edges.first.sections.first.bend_points

        expect(bends.map(&:x)).to all(be > node.center_x)
      end
    end
  end

  describe "DiagramRegistry integration" do
    it "has flowchart registered" do
      expect(Sirena::DiagramRegistry.registered?(:flowchart)).to be true
    end

    it "retrieves flowchart handlers" do
      handlers = Sirena::DiagramRegistry.get(:flowchart)

      expect(handlers).not_to be_nil
      expect(handlers[:parser]).to eq(described_class)
      expect(handlers[:transform]).to eq(Sirena::Layout::Flowchart)
      expect(handlers[:renderer]).to eq(Sirena::Renderer::Flowchart)
    end
  end

  describe "an empty flowchart" do
    corpus_dir = SpecSupport::RepositoryPaths.path("spec/mermaid/flowchart")

    empty_sources = {
      "147 (declare a class)" =>
        File.read("#{corpus_dir}/flow_style_spec-9a4da99b.mmd"),
      "148 (declare multiple classes)" =>
        File.read("#{corpus_dir}/flow_style_spec-0a9a30d4.mmd"),
      "149 (declare a class with a dot in the style)" =>
        File.read("#{corpus_dir}/flow_style_spec-82b844b5.mmd"),
      "150 (declare a class with a space in the style)" =>
        File.read("#{corpus_dir}/flow_style_spec-60fbb77e.mmd"),
      "a bare header" => "graph TD\n",
      "a header with only a comment" => "flowchart LR\n%% just a comment\n",
      "class without a matching classDef" => "graph TD\nclass A foo\n",
    }.freeze

    # mmdc draws the same source 16px square (its 8px padding either side)
    # at viewBox `-8 -8 16 16`; sirena's viewBox origin is always 0 0.
    empty_canvas_attributes = {
      "width" => "16.0", "height" => "16.0", "viewBox" => "0 0 16.0 16.0"
    }.freeze

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

      expect { Sirena::Engine.new.render(source) }
        .to raise_error(Sirena::Layout::LayoutError)
    end
  end
end
