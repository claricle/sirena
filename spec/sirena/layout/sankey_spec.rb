# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Sankey do
  def node(id, label = nil)
    Sirena::Diagram::SankeyNode.new(id, label)
  end

  def flow(source, target, value)
    Sirena::Diagram::SankeyFlow.new(source, target, value)
  end

  def diagram(nodes:, flows:, title: nil)
    Sirena::Diagram::Sankey.new.tap do |item|
      item.nodes = nodes
      item.flows = flows
      item.title = title
      item.acc_title = "Accessible flow"
      item.acc_description = "How values move"
    end
  end

  let(:empty_scene) do
    empty = diagram(nodes: [], flows: [], title: "Nothing yet")
    described_class.new.send(:scene, empty)
  end

  let(:acyclic_scene) do
    subject = diagram(
      nodes: [node("source"), node("middle", "Processor"), node("sink")],
      flows: [flow("source", "middle", 10), flow("middle", "sink", 2.5)],
    )
    described_class.new.call(subject)
  end

  let(:cyclic_scene) do
    subject = diagram(
      nodes: [node("a"), node("b")],
      flows: [flow("a", "b", 3), flow("b", "a", 1), flow("a", "a", 2)],
    )
    described_class.new.call(subject)
  end

  let(:empty_canvas) do
    {
      width: 520.0,
      height: 460.0,
      view_box: "0 0 520 460",
      acc_title: "Accessible flow",
      acc_description: "How values move",
      nodes: [],
      flows: [],
    }
  end
  let(:self_loop_attributes) do
    { self_loop: true, path: nil, label: nil, colour_index: 2 }
  end

  def scene_summary(input)
    scene = described_class.new.call(input)
    [scene.nodes.map { |item| [item.id, item.x, item.y] },
     scene.flows.map { |item| [item.source, item.target, item.width] }]
  end

  def compatibility_summaries(nodes:, flows:)
    direct = diagram(nodes: nodes, flows: flows)
    graph = Sirena::Notation::Mermaid::IRAdapter.call(:sankey, direct)
    [direct, graph].map { |input| scene_summary(input) }
  end

  it "builds the empty accessibility canvas" do
    expect(empty_scene).to have_attributes(empty_canvas)
  end

  it "positions the empty canvas title" do
    expect(empty_scene.title).to have_attributes(
      text: "Nothing yet", x: 260.0, y: 40.0,
    )
  end

  it "assigns acyclic layers" do
    layers = acyclic_scene.nodes.map { |item| [item.id, item.layer, item.x] }

    expect(layers)
      .to eq([["source", 0, 60.0], ["middle", 1, 210.0], ["sink", 2, 360.0]])
  end

  it "uses the explicit node label" do
    expect(acyclic_scene.nodes[1]).to have_attributes(label: have_attributes(
      text: "Processor",
    ))
  end

  it "scales flow widths" do
    expect(acyclic_scene.flows.map(&:width)).to eq([50.0, 14.0])
  end

  it "formats flow labels" do
    expect(acyclic_scene.flows.map { |item| item.label.text })
      .to eq(["10", "2.5"])
  end

  it "builds flow paths" do
    expect(acyclic_scene.flows).to all(have_attributes(path: start_with("M ")))
  end

  it "keeps cycles on the fallback layer" do
    expect(cyclic_scene.nodes.map { |item| [item.id, item.layer] })
      .to eq([["a", 0], ["b", 0]])
  end

  it "marks self-loops" do
    expect(cyclic_scene.flows.last).to have_attributes(self_loop_attributes)
  end

  it "marks non-loop flows" do
    expect(cyclic_scene.flows.first).to have_attributes(
      self_loop: false, colour_index: 0,
    )
  end

  it "lays out shared IR without changing direct Diagram compatibility" do
    summaries = compatibility_summaries(
      nodes: [node("source"), node("sink")],
      flows: [flow("source", "sink", 10)],
    )
    expect(summaries.uniq.one?).to be(true)
  end
end
