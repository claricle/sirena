# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::GitGraph, :aggregate_failures do
  def case_ids
    %w[
      gitgraph/gitgraph_spec-215c1704.mmd
      gitgraph/gitgraph_spec-302c1b10.mmd
      gitgraph/gitgraph_spec-3a0ec594.mmd
      gitgraph/gitgraph_spec-4f488ecd.mmd
      gitgraph/gitgraph_spec-72051fc1.mmd
      gitgraph/gitgraph_spec-c9730706.mmd
      gitgraph/gitgraph_spec-ef884d70.mmd
      gitgraph/should_handle_merge_tags-7d11784d.mmd
      gitgraph/should_handle_merge_with_custom_ids_tags_and_typ-2e8ba4b5.mmd
      gitgraph/should_log_a_warning_when_two_commits_have_the_s-8c8c51d0.mmd
    ]
  end

  def results
    runner = SpecSupport::LayoutParity::CohortRunner.new
    selected = runner.candidate_cases.select do |entry|
      case_ids.include?(entry.case_id)
    end
    selected.to_h { |entry| [entry.case_id, runner.send(:compare, entry)] }
  end

  def scene_for(source)
    diagram = Sirena::Parser::GitGraph.new.parse(source)
    described_class.new.call(diagram)
  end

  def parity_evidence
    [results.keys.sort, results.values.any?(&:hard_failure?),
     center_errors.max, residual_errors.max]
  end

  def center_errors
    results.values.map { |result| result.geometry.fetch(:worst_e_c) }
  end

  def residual_errors
    results.values.flat_map do |result|
      result.geometry.values_at(
        :worst_e_w, :worst_e_h, :worst_e_a, :worst_analog
      )
    end
  end

  it "matches Mermaid's diagonal commit labels across multi-commit graphs" do
    expect(parity_evidence)
      .to match([case_ids.sort, false, (be <= 0.08), (be <= 0.000000000001)])
  end

  it "rotates explicit IDs outside the specialized linear graph shape" do
    scene = scene_for(<<~MERMAID)
      gitGraph
        commit id: "one"
        branch feature
        commit id: "two"
        checkout main
        commit id: "three"
        checkout feature
        merge main
    MERMAID

    labels = scene.commits.flat_map(&:labels).select { |label| label.kind == "id" }
      .to_h { |label| [label.text, label] }
    explicit = labels.values_at("one", "two", "three")

    expect([
      explicit.map { |label| [label.rotation, label.text_anchor] }.uniq,
      labels.fetch("commit-4").rotation,
    ]).to eq([[[-45.0, "start"]], nil])
  end

  it "keeps explicit-ID lane clearance with tags and marker types" do
    scene = scene_for(<<~MERMAID)
      gitGraph
        commit id: "one" tag: "v1"
        commit id: "two" type: REVERSE
        commit id: "three" type: HIGHLIGHT
    MERMAID

    translations = scene.branches.map { |branch| branch.label.translation_x }
    expect(translations).to eq([-47.0])
  end
end
