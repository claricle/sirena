# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::CaseResult do
  subject(:result) do
    described_class.new(
      case_id: "flowchart/example",
      type: "flowchart",
      reference: "spec/fixtures_mermaid/flowchart/example.svg",
      sirena_status: "rendered",
      invariants: [],
      geometry: { matched: 2 },
      reproduce: "bundle exec rspec spec/layout_parity_spec.rb",
    )
  end

  let(:expected_evidence) do
    {
      case: "flowchart/example",
      type: "flowchart",
      reference: "spec/fixtures_mermaid/flowchart/example.svg",
      sirena_status: "rendered",
      invariants: [],
      geometry: { matched: 2 },
      reproduce: "bundle exec rspec spec/layout_parity_spec.rb",
    }
  end
  let(:failure_summary) do
    invariant_failure = result.with(invariants: [{ rule: "element-presence" }])
    render_failure = result.with(
      sirena_status: { error_stage: "render", message: "boom" },
    )
    [result.hard_failure?, invariant_failure.hard_failure?,
     render_failure.hard_failure?]
  end

  it "materializes the settled per-case evidence keys" do
    expect(result.to_h).to eq(expected_evidence)
  end

  it "reports invariant and render hard-gate failures" do
    expect(failure_summary).to eq([false, true, true])
  end
end
