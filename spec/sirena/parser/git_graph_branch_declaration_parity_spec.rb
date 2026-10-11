# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::GitGraph do
  def parse(source)
    described_class.new.parse(source)
  end

  it "switches to a branch declared before the first commit" do
    diagram = parse(<<~MERMAID)
      gitGraph
        branch dev
        branch v2
        branch feat
        commit id: "on-feat"
    MERMAID

    expect(diagram.commits.map { |commit| [commit.id, commit.branch_name] })
      .to eq([["on-feat", "feat"]])
  end

  it "records the declaration point before switching branches" do
    diagram = parse(<<~MERMAID)
      gitGraph
        commit id: "root"
        branch feat
        commit id: "on-feat"
    MERMAID
    branch = diagram.branches.find { |candidate| candidate.name == "feat" }

    expect([branch.parent_branch, branch.created_at_commit])
      .to eq(%w[main root])
  end
end
