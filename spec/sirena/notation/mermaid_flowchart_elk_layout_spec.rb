# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Notation::Mermaid do
  it "selects ELK for the exact lowercase flowchart-elk source header" do
    parsed = described_class.parse("  flowchart-elk TD\n  A --> B\n")

    expect([parsed.type, parsed.layout_engine]).to eq(%i[flowchart elk])
  end

  it "does not select a source layout for an ordinary flowchart" do
    parsed = described_class.parse("flowchart TD\n  A --> B\n")

    expect(parsed.layout_engine).to be_nil
  end
end
