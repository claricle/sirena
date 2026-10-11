# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::CaseComparator do
  subject(:compare) { described_class.compare(**arguments) }

  let(:arguments) do
    {
      case_id: "flowchart/example.mmd",
      type: "flowchart",
      reference: "spec/fixtures_mermaid/flowchart/example.svg",
      reference_svg: '<svg viewBox="0 0 1 1"/>',
      sirena_svg: nil,
      reproduce: "bundle exec rake 'corpus[flowchart,valid]'",
      recognizer: SpecSupport::LayoutParity::FlowchartRecognizer.new,
    }
  end

  it "rejects a missing candidate without render-error evidence" do
    expect { compare }
      .to raise_error(ArgumentError, "sirena svg or render error is required")
  end
end
