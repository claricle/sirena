# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::ErDiagram do
  include LayoutIrShorthand

  let(:id_column) { { name: "id", attribute_type: "int" } }

  describe "relationships built from an IR graph" do
    subject(:scene_edges) { described_class.new.to_graph(graph).edges }

    let(:graph) { ir_graph(id: "er", nodes: nodes, edges: edges) }
    let(:nodes) do
      [
        ir_node(id: "A", label: "A", role: "entity"),
        ir_node(id: "B", label: "B", role: "entity"),
        ir_node(id: "rel", role: "relationship"),
        ir_node(id: "kind", label: "custom", role: "relationship_type",
                parent_id: "rel"),
        ir_node(id: "from", label: "one", role: "source_cardinality",
                parent_id: "rel"),
      ]
    end
    let(:edges) do
      [
        ir_edge(id: "plain", source_id: "A", target_id: "B"),
        ir_edge(id: "named", source_id: "A", target_id: "B",
                parent_id: "rel"),
        ir_edge(id: "strong", source_id: "A", target_id: "B",
                role: "identifying_relationship"),
      ]
    end

    it "defaults to a non-identifying relationship" do
      expect(scene_edges.map(&:relationship_type)).to include("non-identifying")
    end

    it "marks identifying relationships by role" do
      expect(scene_edges.map(&:relationship_type)).to include("identifying")
    end

    it "prefers a stated relationship type over the role" do
      expect(scene_edges.map(&:relationship_type)).to include("custom")
    end

    it "reads cardinality stated on the relationship" do
      expect(scene_edges.map(&:cardinality_from)).to include("one")
    end
  end

  describe ".point" do
    it "returns a Point unchanged" do
      point = described_class::Point.new(x: 3, y: 4)
      expect(described_class.point(point)).to equal(point)
    end

    it "reads coordinates from an object" do
      coords = Struct.new(:x, :y).new(7, 8)
      expect(described_class.point(coords).x).to eq(7.0)
    end

    it "defaults a missing coordinate to zero" do
      coords = Struct.new(:x, :y).new(nil, 8)
      expect(described_class.point(coords).x).to eq(0.0)
    end
  end

  describe ".connection_point" do
    it "returns the shared centre for coincident nodes" do
      box = { x: 0, y: 0, width: 100, height: 60 }
      expect(described_class.connection_point(box, box).y).to eq(30.0)
    end

    it "uses the default size for a node without one" do
      point = described_class.connection_point({ x: 0, y: 0 }, { x: 400, y: 0 })
      expect(point.x).to eq(150.0)
    end

    it "reads geometry from typed nodes" do
      from = described_class::Node.new(x: 0, y: 0, width: 50, height: 50)
      to = described_class::Node.new(x: 200, y: 0, width: 50, height: 50)
      expect(described_class.connection_point(from, to).x).to eq(50.0)
    end
  end

  describe "fonts without a usable theme" do
    it "uses 12 when the theme has no typography" do
      row = described_class.attribute_row(0, 0, id_column, theme: Struct.new(:typography).new(nil))
      expect(row.font_size).to eq(12.0)
    end

    it "uses 12 when no theme is registered at all" do
      allow(Sirena::Theme::Registry).to receive(:get).and_return(nil)
      expect(described_class.attribute_row(0, 0, id_column).font_size)
        .to eq(12.0)
    end
  end

  describe ".attribute_row" do
    it "formats the row from the attribute fields" do
      expect(described_class.attribute_row(0, 0, id_column).text)
        .to eq("int id")
    end
  end

  describe ".edge_label" do
    it "centres the unpositioned label above the line" do
      label = described_class.edge_label(
        { labels: [{ text: "owns" }] }, { x: 0, y: 40 }, { x: 100, y: 40 }
      )
      expect([label.x, label.y]).to eq([50.0, 35.0])
    end
  end

  describe "an edge hash with string keys" do
    it "honours a string-keyed sections entry" do
      section = { "startPoint" => { x: 1, y: 2 }, "endPoint" => { x: 3, y: 4 } }
      boxes = [{ id: "A", x: 0, y: 0 }, { id: "B", x: 200, y: 0 }]
      edge = { sources: ["A"], targets: ["B"], "sections" => [section] }
      scene = described_class.from_graph({ children: boxes, edges: [edge] })
      expect(scene.edges.first.sections.first.end_point.x).to eq(3.0)
    end
  end
end
