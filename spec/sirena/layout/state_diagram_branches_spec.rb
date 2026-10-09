# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::StateDiagram do
  def state(id, x, state_type, labels: [])
    {
      id: id, x: x, y: 10, width: 60, height: 40, labels: labels,
      metadata: { state_type: state_type, shape_type: state_type }
    }
  end

  def transition(id, source, target, extra = {})
    { id: id, sources: [source], targets: [target] }.merge(extra)
  end

  it "emits normal, fork, join, and terminal node geometry" do
    children = [
      state("normal", 0, "normal", labels: [{ text: "Normal" }]),
      state("fork", 100, "fork"),
      state("join", 200, "join"),
      state("start", 300, "start"),
      state("end", 400, "end"),
    ]

    nodes = described_class.from_graph({ children: children, edges: [] })
      .children.to_h { |node| [node.id, node] }

    expect(nodes.fetch("normal").labels.first.text).to eq("Normal")
    expect(nodes.fetch("fork"))
      .to have_attributes(shape_y: 25.0, shape_height: 10.0)
    expect(nodes.fetch("join"))
      .to have_attributes(shape_y: 25.0, shape_height: 10.0)
    expect(nodes.fetch("start").radius).to eq(20.0)
    expect(nodes.fetch("end").inner_radius).to eq(15.0)
  end

  it "uses supplied multi-sections and fallback paths in both directions" do
    children = [state("A", 0, "normal"), state("B", 200, "normal")]
    sections = [
      {
        startPoint: { x: 60, y: 30 }, endPoint: { x: 120, y: 70 },
        bendPoints: [{ x: 90, y: 50 }]
      },
      { startPoint: { x: 120, y: 70 }, endPoint: { x: 200, y: 30 } },
    ]
    edges = [
      transition("routed", "A", "B", sections: sections),
      transition("forward", "A", "B"),
      transition("backward", "B", "A"),
    ]

    by_id = described_class.from_graph({ children: children, edges: edges })
      .edges.to_h { |edge| [edge.id, edge] }

    expect(by_id.fetch("routed").sections.length).to eq(2)
    expect(by_id.fetch("routed").path)
      .to eq("M 60 30 L 90 50 L 120 70 M 120 70 L 200 30")
    expect(by_id.fetch("forward").path).to eq("M 30 30 L 230 30")
    expect(by_id.fetch("backward").path).to eq("M 230 30 L 30 30")
  end

  it "filters missing endpoints and handles labelled and unlabelled edges" do
    children = [state("A", 0, "normal"), state("B", 200, "normal")]
    labels = [{ text: "go", width: 12, height: 10 }]
    labelled = transition(
      "labelled",
      "A",
      "B",
      labels: labels,
      metadata: { trigger: "click", guard_condition: "ready" },
    )
    edges = [
      labelled,
      transition("plain", "A", "B"),
      transition("missing-source", "none", "B"),
      transition("missing-target", "A", "none"),
    ]

    scene_edges = described_class.from_graph({ children: children, edges: edges })
      .edges

    expect(scene_edges.map(&:id)).to eq(%w[labelled plain])
    expect(scene_edges.first.labels.first)
      .to have_attributes(text: "go", x: 130.0, y: 22.0)
    expect([scene_edges.first.trigger, scene_edges.first.guard_condition])
      .to eq(%w[click ready])
    expect(scene_edges.last.labels).to be_empty
  end
end
