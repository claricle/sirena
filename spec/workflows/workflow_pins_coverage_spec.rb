# frozen_string_literal: true

require "yaml"
require_relative "../../scripts/check_workflow_pins"

RSpec.describe WorkflowPins do
  let(:workflow) do
    YAML.safe_load_file(File.expand_path("../../.github/workflows/ci.yml",
                                         __dir__))
  end
  let(:coverage) { workflow.fetch("jobs").fetch("coverage") }
  let(:steps) { coverage.fetch("steps") }
  let(:guard) do
    steps.find { |step| step["run"] == "bundle exec rake coverage:guard" }
  end
  let(:expected_base) do
    "${{ github.event.pull_request.base.sha || " \
      "github.event.merge_group.base_sha || " \
      "(github.event_name == 'push' && github.event.before != " \
      "'0000000000000000000000000000000000000000' && " \
      "github.event.before) || 'HEAD^' }}"
  end

  it "requires coverage in full-lane" do
    needs = workflow.fetch("jobs").fetch("full-lane").fetch("needs")

    expect(needs).to include("coverage")
  end

  it "fails the lane when the corpus-excluded coverage guard fails" do
    expect([coverage.values_at("if", "continue-on-error", "strategy"),
            guard.values_at("if", "continue-on-error")])
      .to eq([[nil, nil, nil], [nil, nil]])
  end

  it "fetches the merge ancestry required by changed-line coverage" do
    checkout = steps.find do |step|
      step["uses"].to_s.start_with?("actions/checkout@")
    end
    expect(checkout.dig("with", "fetch-depth")).to eq(0)
  end

  it "uses the event base and falls back to the preceding commit" do
    expect(guard.dig("env", "COVERAGE_BASE")).to eq(expected_base)
  end
end
