# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/git_graph"
require "sirena/layout/git_graph"

RSpec.describe Sirena::Layout::GitGraph do
  def scene_for(orientation)
    source = <<~MERMAID
      gitGraph #{orientation}:
        commit id: "one"
        commit id: "two"
        commit id: "three"
    MERMAID
    diagram = Sirena::Parser::GitGraph.new.parse(source)
    described_class.new.call(diagram)
  end

  def branch_label_evidence(scene)
    label = scene.branches.fetch(0).label
    first = scene.commits.fetch(0)
    [label.x - first.x, label.y - first.y, label.text_anchor, label.font_size]
  end

  it "anchors horizontal branch labels before the time axis" do
    scene = scene_for("LR")

    expect(branch_label_evidence(scene))
      .to eq([-36.172, -10.5, "start", 16.0])
  end

  it "anchors top-to-bottom branch labels at the top boundary" do
    scene = scene_for("TB")
    label = scene.branches.fetch(0).label
    first = scene.commits.fetch(0)

    expect([label.x - first.x, label.y - first.y, label.text_anchor])
      .to eq([-17.336, -40.0, "start"])
  end

  it "anchors bottom-to-top branch labels at the bottom boundary" do
    scene = scene_for("BT")
    label = scene.branches.fetch(0).label
    first = scene.commits.fetch(0)

    expect([label.x - first.x, label.y - first.y, label.text_anchor])
      .to eq([-17.336, 40.0, "start"])
  end
end
