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

  it "builds the empty titled accessibility canvas" do
    empty = diagram(nodes: [], flows: [], title: "Nothing yet")
    scene = described_class.new.send(:scene, empty)

    expect(scene).to have_attributes(
      width: 520.0,
      height: 460.0,
      view_box: "0 0 520 460",
      acc_title: "Accessible flow",
      acc_description: "How values move",
      nodes: [],
      flows: [],
    )
    expect(scene.title).to have_attributes(text: "Nothing yet", x: 260.0,
                                           y: 40.0)
  end

  it "assigns acyclic layers and proportional geometry" do
    subject = diagram(
      nodes: [node("source"), node("middle", "Processor"), node("sink")],
      flows: [flow("source", "middle", 10), flow("middle", "sink", 2.5)],
    )
    scene = described_class.new.call(subject)

    expect(scene.nodes.map { |item| [item.id, item.layer, item.x] }).to eq(
      [["source", 0, 60.0], ["middle", 1, 210.0], ["sink", 2, 360.0]],
    )
    expect(scene.nodes[1]).to have_attributes(label: have_attributes(
      text: "Processor",
    ))
    expect(scene.flows.map(&:width)).to eq([50.0, 14.0])
    expect(scene.flows.map { |item| item.label.text }).to eq(["10", "2.5"])
    expect(scene.flows).to all(have_attributes(path: start_with("M ")))
  end

  it "keeps cycles and self-loops on the fallback layer" do
    subject = diagram(
      nodes: [node("a"), node("b")],
      flows: [flow("a", "b", 3), flow("b", "a", 1), flow("a", "a", 2)],
    )
    scene = described_class.new.call(subject)

    expect(scene.nodes.map { |item| [item.id, item.layer] })
      .to eq([["a", 0], ["b", 0]])
    expect(scene.flows.last).to have_attributes(
      self_loop: true,
      path: nil,
      label: nil,
      colour_index: 2,
    )
    expect(scene.flows.first).to have_attributes(self_loop: false,
                                                 colour_index: 0)
  end
end
