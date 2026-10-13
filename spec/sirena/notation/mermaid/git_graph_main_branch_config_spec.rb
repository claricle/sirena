# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Notation::Mermaid do
  def parse(source)
    described_class.parse(source).diagram
  end

  def labels(graph, role)
    graph.nodes.select { |node| node.role == role }.map(&:label)
  end

  let(:configured_source) do
    <<~MERMAID
      %%{init: { "gitGraph": { "mainBranchName": "APA" }}}%%
      gitGraph
        commit id: "root"
        branch feature
        commit id: "work"
        checkout APA
        commit id: "release"
    MERMAID
  end
  let(:graph) { parse(configured_source) }
  let(:scene) { Sirena::Layout::GitGraph.new.call(graph) }

  it "uses the configured Git Graph main branch throughout the pipeline" do
    expect([labels(graph, "main_branch"), labels(graph, "branch"),
            labels(graph, "branch_name"), scene.branches.map(&:name)])
      .to eq([["APA"], %w[APA feature], %w[APA feature APA],
              %w[APA feature]])
  end

  it "keeps main as the root when no directive overrides it" do
    graph = parse("gitGraph\n  commit id: \"root\"\n")

    expect([labels(graph, "main_branch"), labels(graph, "branch")])
      .to eq([["main"], ["main"]])
  end
end
