# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::GitGraph do
  def parse(source)
    described_class.new.parse(source)
  end

  context "when switches to a branch declared before the first commit" do
    let(:diagram) do
      parse(<<~MERMAID)
        gitGraph
          branch dev
          branch v2
          branch feat
          commit id: "on-feat"
      MERMAID
    end

    it "retains map" do
      expect(diagram.commits.map { |commit| [commit.id, commit.branch_name] })
        .to eq([["on-feat", "feat"]])
    end
  end

  context "when records the declaration point before switching branches" do
    let(:diagram) do
      parse(<<~MERMAID)
        gitGraph
          commit id: "root"
          branch feat
          commit id: "on-feat"
      MERMAID
    end

    it "retains branch.parent_branch branch.created_at_commit" do
      branch = diagram.branches.find { |candidate| candidate.name == "feat" }

      expect([branch.parent_branch, branch.created_at_commit])
        .to eq(%w[main root])
    end
  end
end
