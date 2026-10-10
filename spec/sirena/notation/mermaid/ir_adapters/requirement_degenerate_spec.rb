# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/mermaid/ir_adapters/requirement"

RSpec.describe Sirena::Notation::Mermaid::IRAdapters::Requirement do
  it "falls back to a generic id for an empty diagram id" do
    diagram = Sirena::Diagram::Requirement.new(id: "")

    expect(described_class.call(diagram).id).to eq("item")
  end
end
