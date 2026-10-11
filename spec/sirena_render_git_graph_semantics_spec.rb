# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena do
  def parse_git_graph(source)
    Sirena::Parser::GitGraph.new.parse(source)
  end

  def merge_commit_source
    <<~MERMAID
      gitGraph
        commit id: "ZERO"
        branch feature
        commit id: "B"
        checkout main
        merge feature id: "M"
    MERMAID
  end

  def feature_branch_source
    <<~MERMAID
      gitGraph
        commit id: "MAIN"
        branch develop
        commit id: "DEV"
        checkout main
        branch feature
    MERMAID
  end

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
      source = File.read(File.join("spec/mermaid/gitgraph", fixture))

      expect { described_class.render(source) }
        .to raise_error(Sirena::Parser::ParseError, message)
    end
  end

  {
    "gitgraph_spec-076af5a8.mmd" =>
      %w[1-abcdefg 2-abcdefg commit-3 commit-4],
    "gitgraph_spec-215c1704.mmd" =>
      %w[1-abcdefg 2-abcdefg commit-3 commit-4],
    "should_handle_cases_when_merge_is_a_noop-9267428e.mmd" =>
      %w[commit-1 commit-2 commit-3 commit-4],
  }.each do |fixture, expected_ids|
    it "draws the oracle-valid ancestor merge in #{fixture}" do
      source = File.read(File.join("spec/mermaid/gitgraph", fixture))
      diagram = Sirena::Parser::GitGraph.new.parse(source)

      expect(diagram.commits.map(&:id)).to eq(expected_ids)
    end
  end

  it "keeps the later duplicate in " \
     "should_log_a_warning_when_two_commits_have_the_s-8c8c51d0.mmd" do
    fixture = "should_log_a_warning_when_two_commits_have_the_s-8c8c51d0.mmd"
    source = File.read(File.join("spec/mermaid/gitgraph", fixture))
    diagram = Sirena::Parser::GitGraph.new.parse(source)
    scene = Sirena::Layout::GitGraph.new.call(diagram)

    expect(scene.commits.map(&:id).count("working on MDR")).to eq(1)
  end

  it "records both parents on a merge commit" do
    diagram = parse_git_graph(merge_commit_source)
    expect(diagram.commits.last.parent_ids).to eq(%w[ZERO B])
  end

  it "creates a branch from the checked-out branch tip" do
    diagram = parse_git_graph(feature_branch_source)
    feature = diagram.branches.find { |branch| branch.name == "feature" }
    expect(feature.created_at_commit).to eq("MAIN")
  end
end
