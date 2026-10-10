# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::GitGraph do
  subject(:layout) { described_class.new }

  def empty_evidence
    scene = layout.call(Sirena::Diagram::GitGraph.new)
    main = scene.branches.fetch(0)
    [scene.width, scene.height, scene.commits, scene.connections,
     [main.name, main.lane, main.label]]
  end

  def top_to_bottom_scene
    commit = Sirena::Diagram::GitGraph::Commit.new(
      id: "A", tag: "v1", branch_name: "main",
    )
    diagram = Sirena::Diagram::GitGraph.new(
      orientation: "TB", commits: [commit],
    )
    layout.call(diagram)
  end

  def vertical_label_evidence
    scene = top_to_bottom_scene
    commit = scene.commits.fetch(0)
    labels = commit.labels.to_h { |label| [label.kind, label] }
    [labels.values_at("tag", "id").map(&:text_anchor),
     labels_on_opposite_sides?(labels, commit), branch_below?(scene, commit)]
  end

  def labels_on_opposite_sides?(labels, commit)
    labels["tag"].x < commit.x && labels["id"].x > commit.x
  end

  def branch_below?(scene, commit)
    scene.branches.fetch(0).label.y > commit.y
  end

  it "returns a finite empty graph with unlabeled main-branch metadata" do
    expect(empty_evidence).to eq([240.0, 200.0, [], [], ["main", 0, nil]])
  end

  it "places top-to-bottom tag and identity labels on opposite sides" do
    expect(vertical_label_evidence).to eq([%w[end start], true, true])
  end
end
