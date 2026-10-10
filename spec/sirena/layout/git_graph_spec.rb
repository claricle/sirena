# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/git_graph"
require "sirena/layout/git_graph"

RSpec.describe Sirena::Layout::GitGraph do
  let(:source) do
    <<~MERMAID
      gitGraph BT:
        accTitle: Git history
        accDescr: Branching history
        commit id: "A" tag: "v1" msg: "start"
        branch feature order: 2
        checkout feature
        commit id: "B" type: HIGHLIGHT msg: "work"
        checkout main
        commit id: "C" type: REVERSE
        merge feature id: "M" tag: "merged"
        cherry-pick id: "B" parent: "A" tag: "picked"
    MERMAID
  end
  let(:diagram) { Sirena::Parser::GitGraph.new.parse(source) }
  let(:ir) do
    Sirena::Notation::Mermaid::IRAdapters::GitGraph.call(diagram)
  end
  let(:layout) { described_class.new }

  def commit_summary
    commits = layout.call(ir).commits
    [commits.map(&:id), commits.map(&:message), commits.map(&:type),
     commits.map(&:tag), commits.map(&:parent_ids)]
  end

  def expected_commits
    [%w[A B C M B], ["start", "work", nil, nil, nil],
     %w[NORMAL HIGHLIGHT REVERSE NORMAL NORMAL],
     ["v1", nil, nil, "merged", "picked"],
     [[], [], ["A"], ["C"], ["M"]]]
  end

  def action_summary
    scene = layout.call(ir)
    merge_commit, cherry_pick = scene.commits.last(2)
    connections = scene.connections.map do |edge|
      [edge.source, edge.target, edge.type]
    end
    [[merge_commit.is_merge, merge_commit.merge_branch],
     [cherry_pick.is_cherry_pick, cherry_pick.cherry_pick_parent], connections]
  end

  def expected_actions
    [[true, "feature"], [true, "A"],
     [["A", "C", :normal], ["C", "M", :merge],
      ["M", "B", :cherry_pick]]]
  end

  def branch_summary
    branches = layout.call(ir).branches
    [branches.map(&:name), branches.map(&:lane),
     [branches.last.order, branches.last.parent_branch,
      branches.last.created_at_commit]]
  end

  it "produces byte-identical Scenes from the private model and shared IR" do
    from_diagram = layout.call(diagram)
    from_ir = layout.call(ir)

    expect(Marshal.dump(from_ir)).to eq(Marshal.dump(from_diagram))
  end

  it "preserves commit order, identity, messages, types, tags, and parents" do
    expect(commit_summary).to eq(expected_commits)
  end

  it "preserves merge and cherry-pick semantics and resolved endpoints" do
    expect(action_summary).to eq(expected_actions)
  end

  it "preserves branch metadata and assigns lanes only during layout" do
    expect(branch_summary)
      .to eq([%w[main feature], [0, 1], [2, "main", "A"]])
  end

  it "applies bottom-to-top orientation without mutating either input" do
    before = [Marshal.dump(diagram), Marshal.dump(ir)]
    scene = layout.call(ir)
    unchanged = [Marshal.dump(diagram), Marshal.dump(ir)] == before

    expect([scene.commits.map(&:y) == scene.commits.map(&:y).sort.reverse,
            unchanged]).to eq([true, true])
  end
end
