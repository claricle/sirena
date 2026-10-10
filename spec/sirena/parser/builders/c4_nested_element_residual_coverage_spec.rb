# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Builders::C4 do
  let(:tree) do
    [{ boundary_type: "Boundary", id: "outer",
       body: [{ item: { element_type: "System" } }] }]
  end

  it "keeps an id-less nested element out of membership ids" do
    diagram = described_class.new.apply(tree)
    evidence = [diagram.elements.first.id,
                diagram.boundaries.first.element_ids]
    expect(evidence).to eq([nil, []])
  end
end
