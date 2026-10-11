# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::GitGraph do
  subject(:scene) do
    diagram = Sirena::Parser::GitGraph.new.parse(<<~MERMAID)
      gitGraph:
        commit
    MERMAID
    described_class.new.call(diagram)
  end

  it "gives a lone main-branch label Mermaid's single-commit clearance" do
    label = scene.branches.fetch(0).label
    commit = scene.commits.fetch(0)

    expect((label.x - commit.x).round(3)).to eq(-86.172)
  end
end
