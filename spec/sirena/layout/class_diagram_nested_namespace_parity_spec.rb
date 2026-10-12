# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::ClassDiagram do
  subject(:parity_summary) do
    metrics = result.geometry
    [namespace_identity, result.hard_failure?,
     metrics.fetch(:worst_e_c) <= 0.08,
     metrics.fetch(:worst_e_w) <= 0.15,
     metrics.fetch(:worst_e_h) <= 0.15]
  end

  let(:case_id) { "unknown/classdiagram_spec-cce899ec.mmd" }
  let(:source) { File.read("spec/mermaid/#{case_id}") }
  let(:scene) do
    described_class.new.call(Sirena::Parser::ClassDiagram.new.parse(source))
  end
  let(:namespace_identity) do
    boxes = scene.namespaces.map { |box| [box.id, box.title] }
    group_ids = Sirena.render(source).scan(/<g id="namespace-([^"]+)">/).flatten
    [boxes, group_ids]
  end
  let(:result) do
    runner = SpecSupport::LayoutParity::CohortRunner.new
    candidate = runner.candidate_cases.find { |item| item.case_id == case_id }
    runner.send(:compare, candidate)
  end

  def expected_summary
    [
      [
        [
          ["namespace:Company", "Company"],
          ["namespace:Company.Project", "Project"],
          ["namespace:Company.Project.Module", "Module"],
          ["namespace:Company.Project.Module.SubModule", "SubModule"],
        ],
        %w[Company Company.Project Company.Project.Module
           Company.Project.Module.SubModule],
      ],
      false, true, true, true
    ]
  end

  it "nests dotted namespace segments within the Class parity thresholds" do
    expect(parity_summary).to eq(expected_summary)
  end
end
