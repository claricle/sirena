# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::GitGraph, :aggregate_failures do
  def case_ids
    %w[
      gitgraph/gitgraph_spec-a80be08a.mmd
      gitgraph/gitgraph_spec-fcc2f0dd.mmd
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

  it "matches Mermaid's fully tagged single-lane vertical labels" do
    errors = results.values.map { |result| result.geometry.fetch(:worst_e_c) }

    expect([results.keys.sort, results.values.any?(&:hard_failure?), errors.max])
      .to match([case_ids.sort, false, (be <= 0.08)])
  end

  it "rotates tags only for the fully tagged single-lane vertical mode" do
    fully_tagged = scene_for(<<~MERMAID)
      gitGraph TB:
        commit id: "one" tag: "v1"
        commit id: "two" tag: "v2"
    MERMAID
    partially_tagged = scene_for(<<~MERMAID)
      gitGraph TB:
        commit id: "one" tag: "v1"
        commit id: "two"
    MERMAID

    rotations = fully_tagged.commits.flat_map(&:labels)
      .select { |label| label.kind == "tag" }.map(&:rotation)
    partial = partially_tagged.commits.flat_map(&:labels)
      .find { |label| label.kind == "tag" }

    expect([rotations, partial.rotation, partial.text_anchor])
      .to eq([[45.0, 45.0], nil, "end"])
  end
end
