# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::ClassDiagram do
  let(:children) do
    [
      { id: "A", x: 0, y: 0, width: 120, height: 70 },
      { id: "B", x: 240, y: 0, width: 120, height: 70 },
    ]
  end

  def relation(id, metadata = {}, sections: nil)
    edge = {
      id: id, sources: ["A"], targets: ["B"], metadata: metadata
    }
    edge[:sections] = sections if sections
    edge
  end

  describe "routed coordinates" do
    let(:snake) do
      {
        start_point: { x: 120, y: 20 },
        end_point: { x: 240, y: 20 },
        bend_points: [{ x: 180, y: 30 }],
      }
    end
    let(:camel) do
      {
        "startPoint" => { x: 120, y: 40 },
        "endPoint" => { x: 240, y: 40 },
        "bendPoints" => [{ x: 180, y: 50 }],
      }
    end
    let(:edges) do
      [
        relation("snake", sections: [snake]),
        relation("camel", sections: [camel]),
        relation("fallback"),
      ]
    end
    let(:sections) do
      described_class.from_graph({ children: children, edges: edges })
        .edges.to_h { |edge| [edge.id, edge.sections.first] }
    end

    it "accepts snake-case routed coordinates" do
      expect(sections.fetch("snake").bend_points.first.y).to eq(30.0)
    end

    it "accepts camel-case routed coordinates" do
      expect(sections.fetch("camel").bend_points.first.y).to eq(50.0)
    end

    it "builds fallback start coordinates" do
      expect(sections.fetch("fallback").start_point.x).to eq(120.0)
    end

    it "builds fallback end coordinates" do
      expect(sections.fetch("fallback").end_point.x).to eq(240.0)
    end
  end

  describe "relation types" do
    let(:types) do
      %w[inheritance realization composition aggregation dependency]
    end
    let(:edges) do
      types.map { |type| relation(type, { relationship_type: type }) }
    end
    let(:relations) do
      described_class.from_graph({ children: children, edges: edges })
        .edges.to_h { |edge| [edge.id, edge] }
    end

    it "fills inheritance markers" do
      expect(relations.fetch("inheritance").markers.first.fill).to eq("#000000")
    end

    it "leaves realization markers hollow" do
      expect(relations.fetch("realization").markers.first.fill).to eq("#ffffff")
    end

    it "fills composition markers" do
      expect(relations.fetch("composition").markers.first.fill).to eq("#000000")
    end

    it "leaves aggregation markers hollow" do
      expect(relations.fetch("aggregation").markers.first.fill).to eq("#ffffff")
    end

    it "keeps dependency relations markerless" do
      expect(relations.fetch("dependency").markers).to be_empty
    end

    it "dashes dependency relations" do
      expect(relations.fetch("dependency").dashed).to be(true)
    end
  end

  describe "mixed terminal markers" do
    let(:metadata) do
      {
        start_marker: "composition",
        end_marker: "dependency",
        dashed: true,
      }
    end
    let(:edge) do
      graph = { children: children, edges: [relation("mixed", metadata)] }
      described_class.from_graph(graph).edges.first
    end

    it "fills both terminal markers" do
      expect(edge.markers.map(&:fill)).to eq(%w[#000000 #000000])
    end

    it "builds both marker polygons" do
      point_counts = edge.markers.map { |marker| marker.points.split.length }
      expect(point_counts).to eq([4, 4])
    end

    it "uses the explicit dashed style" do
      expect(edge.dashed).to be(true)
    end
  end

  describe "an empty class compartment" do
    let(:node) do
      described_class.from_graph({ children: [children.first], edges: [] })
        .children.first
    end

    it "keeps the class name" do
      expect(node.name.text).to eq("A")
    end

    it "omits the stereotype" do
      expect(node.stereotype).to be_nil
    end

    it "keeps attributes empty" do
      expect(node.attributes).to be_empty
    end

    it "keeps methods empty" do
      expect(node.method_rows).to be_empty
    end

    it "uses the name as its only label" do
      expect(node.labels.map(&:text)).to eq(["A"])
    end

    it "retains the compartment separator" do
      expect(node.separators.length).to eq(1)
    end
  end
end
