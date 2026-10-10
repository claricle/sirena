# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::ClassDiagram do
  include LayoutIrShorthand

  let(:children) do
    [
      { id: "A", x: 0, y: 0, width: 120, height: 70 },
      { id: "B", x: 240, y: 0, width: 120, height: 70 },
    ]
  end

  describe "a graph without diagram settings" do
    let(:graph) do
      ir_graph(
        id: "classes",
        nodes: [ir_node(id: "A", label: "A", role: "class")],
      )
    end

    it "still builds the class nodes" do
      expect(described_class.new.to_graph(graph).children.map(&:id))
        .to eq(["A"])
    end
  end

  describe ".connection_point" do
    it "returns the shared centre for coincident nodes" do
      box = { x: 0, y: 0, width: 100, height: 60 }
      point = described_class.connection_point(box, box)
      expect(point).to eq({ x: 50.0, y: 30.0 })
    end

    it "reads geometry from typed nodes" do
      from = described_class::Node.new(x: 0, y: 0, width: 50, height: 50)
      to = described_class::Node.new(x: 200, y: 0, width: 50, height: 50)
      expect(described_class.connection_point(from, to)[:x]).to eq(50.0)
    end
  end

  describe "edge labels" do
    let(:labels) do
      [
        { text: "mid" },
        { text: "near", position: "source" },
        { text: "skipped", position: "elsewhere" },
      ]
    end
    let(:edge) do
      { id: "e", sources: ["A"], targets: ["B"], labels: labels }
    end
    let(:scene_edge) do
      described_class.from_graph({ children: children, edges: [edge] })
        .edges.first
    end

    it "drops a label with an unknown position" do
      expect(scene_edge.labels.map(&:text)).to eq(%w[mid near])
    end
  end

  describe "label fonts" do
    let(:edge) do
      { id: "e", sources: ["A"], targets: ["B"], labels: [{ text: "x" }] }
    end
    let(:size) do
      described_class.from_graph(
        { children: children, edges: [edge] }, theme: theme
      ).edges.first.labels.first.font_size
    end

    context "when the theme has no typography" do
      let(:theme) { Struct.new(:typography).new(nil) }

      it("falls back to 12") { expect(size).to eq(12.0) }
    end

    context "when the font size is not positive" do
      let(:theme) do
        Struct.new(:typography)
          .new(Struct.new(:font_size_small, :font_size_large).new(0, 0))
      end

      it("falls back to 12") { expect(size).to eq(12.0) }
    end
  end

  describe "the class name font" do
    let(:graph) do
      ir_graph(id: "c", nodes: [ir_node(id: "A", label: "A", role: "class")])
    end
    let(:layout) { described_class.new }
    let(:size) { layout.to_graph(graph).children.first.name.font_size }

    it "falls back to 16 when the theme has no typography" do
      layout.theme = Struct.new(:typography).new(nil)
      expect(size).to eq(16.0)
    end

    it "falls back to 16 when no theme is registered at all" do
      allow(Sirena::Theme::Registry).to receive(:get).and_return(nil)
      expect(size).to eq(16.0)
    end
  end

  describe "the label font without any registered theme" do
    it "falls back to 12" do
      allow(Sirena::Theme::Registry).to receive(:get).and_return(nil)
      edge = { id: "e", sources: ["A"], targets: ["B"],
               labels: [{ text: "x" }] }
      scene = described_class.from_graph({ children: children, edges: [edge] })
      expect(scene.edges.first.labels.first.font_size).to eq(12.0)
    end
  end
end
