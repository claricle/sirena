# frozen_string_literal: true

require "spec_helper"
require "sirena/diagram/git_graph"

RSpec.describe Sirena::Diagram::GitGraph do
  subject(:git_graph) { described_class.new }

  describe Sirena::Diagram::GitGraph::Commit do
    it "uses normal non-merge defaults" do
      commit = described_class.new
      attributes = [commit.type, commit.parent_ids,
                    commit.is_merge, commit.is_cherry_pick]

      expect(attributes).to eq(["NORMAL", [], false, false])
    end
  end

  describe Sirena::Diagram::GitGraph::Branch do
    it "retains branch identity and ordering" do
      branch = described_class.new(name: "main", order: 1)

      expect([branch.name, branch.order]).to eq(["main", 1])
    end
  end

  it "starts left-to-right with empty graph collections" do
    expect([git_graph.orientation, git_graph.commits, git_graph.branches])
      .to eq(["LR", [], []])
  end

  it "reports its type and remains valid while validation is deferred" do
    expect([git_graph.diagram_type, git_graph.valid?]).to eq([:git_graph, true])
  end
end
