# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::UserJourney do
  subject(:scene) { described_class.new.to_graph(graph) }

  include LayoutIrShorthand

  let(:graph) { ir_graph(id: "journey", nodes: nodes, edges: edges) }
  let(:nodes) do
    [
      ir_node(id: "plain"),
      ir_node(id: "none", label: "None", role: "journey_task_green"),
      ir_node(id: "half", label: "Half", role: "journey_task_red",
              properties: ir_weight(2.5)),
      ir_node(id: "whole", label: "Whole", role: "journey_task_red",
              properties: ir_weight(4.0)),
    ]
  end
  let(:edges) do
    [
      ir_edge(id: "skip", source_id: "none", target_id: "half",
              role: "other"),
      ir_edge(id: "flow", source_id: "none", target_id: "half",
              role: "sequence"),
    ]
  end
  let(:scores) do
    scene.tasks.to_h { |task| [task.id, task.labels[1].text] }
  end

  it "ignores nodes whose role is not a journey task" do
    expect(scene.tasks.map(&:id)).to eq(%w[none half whole])
  end

  it "draws an arrow only for sequence edges" do
    expect(scene.arrows.map(&:id)).to eq(["flow"])
  end

  it "scores a task with no weight as 3" do
    expect(scores.fetch("none")).to eq("3")
  end

  it "keeps a fractional weight as is" do
    expect(scores.fetch("half")).to eq("2.5")
  end

  it "prints a whole-number weight without a decimal" do
    expect(scores.fetch("whole")).to eq("4")
  end

  it "leaves the section name empty for a task outside any section" do
    expect(scene.tasks.map(&:section_name)).to all(be_nil)
  end
end
