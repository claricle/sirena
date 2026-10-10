# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/git_graph"
require "sirena/notation/mermaid/ir_adapters/git_graph"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::GitGraph do
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
  let(:graph) { described_class.call(diagram) }
  let(:commits) { graph.nodes.select { |node| node.role == "commit" } }
  let(:branches) { graph.nodes.select { |node| node.role == "branch" } }

  def semantics(node)
    graph.nodes.select { |candidate| candidate.parent_id == node.id }
      .group_by(&:role).transform_values { |values| values.map(&:label) }
  end

  def edge_semantics(edge)
    nodes = graph.nodes.to_h { |node| [node.id, node] }
    [nodes.fetch(edge.source_id).label,
     nodes.fetch(edge.target_id).label, edge.role]
  end

  def identity_summary
    ids = [graph, *graph.items].map(&:id)
    [graph.valid?, ids.uniq.size == ids.size,
     commits.map(&:label), branches.map(&:label)]
  end

  def metadata_summary
    graph_metadata + commit_metadata
  end

  def graph_metadata
    orientation = graph.nodes.find { |node| node.role == "orientation" }
    [orientation.label, graph.accessibility_title,
     graph.accessibility_description]
  end

  def commit_metadata
    commits.first(3).map { |commit| semantics(commit) }
  end

  def action_summary
    [graph.edges.map { |edge| edge_semantics(edge) },
     semantics(commits[3]), semantics(commits[4])]
  end

  def expected_metadata
    ["BT", "Git history", "Branching history",
     a_hash_including("message" => ["start"], "type" => ["NORMAL"],
                      "tag" => ["v1"], "branch_name" => ["main"]),
     a_hash_including("message" => ["work"], "type" => ["HIGHLIGHT"],
                      "branch_name" => ["feature"]),
     a_hash_including("type" => ["REVERSE"],
                      "parent_reference" => ["A"])]
  end

  def expected_actions
    [[
      ["A", "C", "parent"], ["C", "M", "merge"],
      ["M", "B", "cherry_pick"]
    ],
     a_hash_including("merge_commit" => ["true"],
                      "merge_branch" => ["feature"]),
     a_hash_including("cherry_pick_commit" => ["true"],
                      "cherry_pick_parent" => ["A"])]
  end

  def expected_branches
    [{ "order" => ["0"] },
     { "order" => ["2"], "parent_branch" => ["main"],
       "created_at_commit" => ["A"] }]
  end

  it "builds a valid collision-safe graph in commit and branch source order" do
    expect(identity_summary)
      .to eq([true, true, %w[A B C M B], %w[main feature]])
  end

  it "preserves orientation, accessibility, and commit semantics" do
    expect(metadata_summary).to match(expected_metadata)
  end

  it "preserves parent, merge, and cherry-pick endpoint semantics" do
    expect(action_summary).to match(expected_actions)
  end

  it "preserves ordered branch metadata" do
    expect(branches.map { |branch| semantics(branch) })
      .to eq(expected_branches)
  end

  it "puts no canvas geometry, measurement, path, lane, or colour in IR" do
    forbidden = %i[x y width height lane color colour path points]
    exposed = [graph, *graph.items].flat_map do |item|
      forbidden.select { |name| item.respond_to?(name) }
    end

    expect(exposed).to eq([])
  end

  it "does not mutate the private source model" do
    before = diagram_snapshot(diagram)

    graph

    expect(diagram_snapshot(diagram)).to eq(before)
  end

  def diagram_snapshot(value)
    Marshal.dump(value)
  end
end
