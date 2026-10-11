# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena do
  fixture_dir = "spec/mermaid/gitgraph"
  {
    "should_fail_cherry_picking_of_merge_commits_if_t-c9fa8ebb.mmd" =>
      /parent/i,
    "should_fail_cherry_picking_of_merge_commits_when-9f5b53c4.mmd" =>
      /parent/i,
    "should_throw_error_when_try_to_checkout_unknown-3e3b849e.mmd" =>
      /unknown branch/i,
    "should_throw_error_when_trying_to_merge_branch_t-950f4997.mmd" =>
      /itself/i,
    "should_throw_error_when_trying_to_merge_branch_w-93bba635.mmd" =>
      /no new commits/i,
    "should_throw_error_when_trying_to_merge_branches-fde8e313.mmd" =>
      /no new commits/i,
    "should_throw_error_when_trying_to_merge_unknown-36f2e03b.mmd" =>
      /unknown branch/i,
    "should_throw_error_when_trying_to_merge_when_cur-4bb16d06.mmd" =>
      /unknown branch/i,
    "should_throw_error_when_using_existing_id_as_mer-5ee3b619.mmd" =>
      /commit id/i,
  }.each do |fixture, message|
    it "rejects pinned-invalid #{fixture}" do
      source = File.read(File.join(fixture_dir, fixture))

      expect { described_class.render(source) }
        .to raise_error(Sirena::Parser::ParseError, message)
    end
  end

  it "records both parents on a merge commit" do
    source = <<~MERMAID
      gitGraph
        commit id: "ZERO"
        branch feature
        commit id: "B"
        checkout main
        merge feature id: "M"
    MERMAID

    diagram = Sirena::Parser::GitGraph.new.parse(source)
    expect(diagram.commits.last.parent_ids).to eq(%w[ZERO B])
  end

  it "creates a branch from the checked-out branch tip" do
    source = <<~MERMAID
      gitGraph
        commit id: "MAIN"
        branch develop
        commit id: "DEV"
        checkout main
        branch feature
    MERMAID

    diagram = Sirena::Parser::GitGraph.new.parse(source)
    feature = diagram.branches.find { |branch| branch.name == "feature" }
    expect(feature.created_at_commit).to eq("MAIN")
  end
end
