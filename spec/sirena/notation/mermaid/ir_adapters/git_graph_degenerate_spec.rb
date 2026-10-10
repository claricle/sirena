# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/git_graph"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::GitGraph do
  let(:commit) do
    Sirena::Diagram::GitGraph::Commit.new(
      id: "c1", branch_name: "main", parent_ids: ["ghost"],
    )
  end
  let(:diagram) { Sirena::Diagram::GitGraph.new(commits: [commit]) }

  it "drops a parent link to a commit that does not exist" do
    expect(described_class.call(diagram).edges).to be_empty
  end
end
