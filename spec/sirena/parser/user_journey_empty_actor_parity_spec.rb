# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::UserJourney, :aggregate_failures do
  let(:source) do
    <<~MERMAID
      journey
        section Work
        Omitted: 5
        Explicit: 5:
        Named: 5: Alice
    MERMAID
  end

  let(:diagram) { described_class.new.parse(source) }
  let(:scene) { Sirena::Layout::UserJourney.new.call(diagram) }

  let(:exact_summary) do
    {
      "hard_failure" => false,
      "metrics" => include(
        "worst_e_c" => 0.0, "worst_e_w" => 0.0,
        "worst_e_h" => 0.0, "worst_e_a" => 0.0
      ),
    }
  end

  it "preserves an explicit empty actor without changing an omitted group" do
    expect(diagram.all_tasks.map(&:actors)).to eq([[], [""], ["Alice"]])
    expect(scene.legend.map { |actor| actor.dot.name }).to eq(["", "Alice"])
    expect(task_dots).to eq("Omitted" => [], "Explicit" => [""],
                            "Named" => ["Alice"])
  end

  it "matches both pinned task-definition references exactly" do
    expect(parity_rows).to all(include("summary" => exact_summary))
  end

  def task_dots
    scene.tasks.to_h do |task|
      [task.labels.first.text, task.dots.map(&:name)]
    end
  end

  def parity_rows
    case_ids = %w[
      user_journey/journey_spec-d58fdd99.mmd
      user_journey/should_handle_a_task_definition-5d163624.mmd
    ]
    runner = SpecSupport::LayoutParity::CohortRunner.new
    results = runner.candidate_cases.filter_map do |candidate|
      runner.send(:compare, candidate) if case_ids.include?(candidate.case_id)
    end
    SpecSupport::LayoutParity::CaseLedger.build(results)
  end
end
