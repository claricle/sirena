# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena do
  %w[
    flow_text_spec-1e40cec6.mmd
    flow_text_spec-6c2697c9.mmd
    flow_text_spec-b7613af6.mmd
    flow_text_spec-cbaf90b9.mmd
    flow_text_spec-e500bc56.mmd
  ].each do |fixture|
    it "rejects the pinned-invalid unquoted parenthesis in #{fixture}" do
      source = File.read(File.join("spec/mermaid/flowchart", fixture))

      expect { described_class.render(source) }
        .to raise_error(Sirena::Parser::ParseError)
    end
  end

  it "renders a parenthesis inside a quoted rectangular label" do
    source = <<~MERMAID
      flowchart LR
      node["hello ) world"] --> target
    MERMAID

    expect(described_class.render(source)).to include("hello ) world")
  end
end
