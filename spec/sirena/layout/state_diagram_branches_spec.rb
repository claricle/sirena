# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::StateDiagram do
  def state(id, x_position, state_type, labels: [])
    {
      id: id, x: x_position, y: 10, width: 60, height: 40, labels: labels,
      metadata: { state_type: state_type, shape_type: state_type }
    }
  end

  def transition(id, source, target, extra = {})
    { id: id, sources: [source], targets: [target] }.merge(extra)
  end

  describe "state node geometry" do
    let(:children) do
      [
        state("normal", 0, "normal", labels: [{ text: "Normal" }]),
        state("fork", 100, "fork"),
        state("join", 200, "join"),
        state("start", 300, "start"),
        state("end", 400, "end"),
      ]
    end
    let(:nodes) do
      described_class.from_graph({ children: children, edges: [] })
        .children.to_h { |node| [node.id, node] }
    end

    it "emits normal node labels" do
      expect(nodes.fetch("normal").labels.first.text).to eq("Normal")
    end

    it "emits fork bar geometry" do
      expect(nodes.fetch("fork"))
        .to have_attributes(shape_y: 25.0, shape_height: 10.0)
    end

    it "emits join bar geometry" do
      expect(nodes.fetch("join"))
        .to have_attributes(shape_y: 25.0, shape_height: 10.0)
    end

    it "emits start node geometry" do
      expect(nodes.fetch("start").radius).to eq(20.0)
    end

    it "emits terminal node geometry" do
      expect(nodes.fetch("end").inner_radius).to eq(15.0)
    end
  end

  describe "transition paths" do
    let(:children) do
      [state("A", 0, "normal"), state("B", 200, "normal")]
    end
    let(:sections) do
      [
        {
          startPoint: { x: 60, y: 30 },
          endPoint: { x: 120, y: 70 },
          bendPoints: [{ x: 90, y: 50 }],
        },
        { startPoint: { x: 120, y: 70 }, endPoint: { x: 200, y: 30 } },
      ]
    end
    let(:edges) do
      [
        transition("routed", "A", "B", sections: sections),
        transition("forward", "A", "B"),
        transition("backward", "B", "A"),
      ]
    end
    let(:transitions) do
      described_class.from_graph({ children: children, edges: edges })
        .edges.to_h { |edge| [edge.id, edge] }
    end

    it "uses all supplied sections" do
      expect(transitions.fetch("routed").sections.length).to eq(2)
    end

    it "joins supplied sections into a path" do
      expect(transitions.fetch("routed").path)
        .to eq("M 60 30 L 90 50 L 120 70 M 120 70 L 200 30")
    end

    it "builds forward fallback paths" do
      expect(transitions.fetch("forward").path).to eq("M 30 30 L 230 30")
    end

    it "builds backward fallback paths" do
      expect(transitions.fetch("backward").path).to eq("M 230 30 L 30 30")
    end
  end

  describe "transition filtering and labels" do
    let(:children) do
      [state("A", 0, "normal"), state("B", 200, "normal")]
    end
    let(:labelled) do
      transition(
        "labelled",
        "A",
        "B",
        labels: [{ text: "go", width: 12, height: 10 }],
        metadata: { trigger: "click", guard_condition: "ready" },
      )
    end
    let(:edges) do
      [
        labelled,
        transition("plain", "A", "B"),
        transition("missing-source", "none", "B"),
        transition("missing-target", "A", "none"),
      ]
    end
    let(:scene_edges) do
      described_class.from_graph({ children: children, edges: edges }).edges
    end

    it "filters transitions with missing endpoints" do
      expect(scene_edges.map(&:id)).to eq(%w[labelled plain])
    end

    it "positions labelled transitions" do
      expect(scene_edges.first.labels.first)
        .to have_attributes(text: "go", x: 130.0, y: 22.0)
    end

    it "preserves transition metadata" do
      metadata = [scene_edges.first.trigger, scene_edges.first.guard_condition]
      expect(metadata).to eq(%w[click ready])
    end

    it "keeps unlabelled transitions label-free" do
      expect(scene_edges.last.labels).to be_empty
    end
  end
end
