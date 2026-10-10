# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/git_graph"

RSpec.describe Sirena::Layout::GitGraph do
  subject(:layout) { described_class.new }

  def graph_without_orientation
    Sirena::IR::Graph.new(
      id: "git_graph", role: "version_history",
      nodes: [
        Sirena::IR::Node.new(
          id: "commit_0",
          label: "commit_0",
          role: "commit",
        ),
      ]
    )
  end

  def horizontal_default_evidence
    scene = layout.call(graph_without_orientation, theme: Sirena::Theme.new)
    commit = scene.commits.fetch(0)
    branch_label = scene.branches.fetch(0).label
    [commit.labels, branch_label.text_anchor, branch_label.font_size]
  end

  def default_small_font_size
    Sirena::Theme::Registry.get(:default).typography.font_size_small
  end

  it "uses horizontal defaults without labeling generated commit ids" do
    expect(horizontal_default_evidence)
      .to eq([[], "start", default_small_font_size])
  end

  it "ignores connections with missing positioned endpoints" do
    edge = Sirena::IR::Edge.new(
      id: "missing_parent", source_id: "missing", target_id: "commit_0",
      role: "parent"
    )

    expect(layout.send(:build_connections, [], [edge])).to be_empty
  end

  it "reserves two lane widths when no lanes are assigned" do
    expect(layout.send(:calculate_lane_span, {}))
      .to eq(described_class::LANE_SPACING * 2)
  end
end
