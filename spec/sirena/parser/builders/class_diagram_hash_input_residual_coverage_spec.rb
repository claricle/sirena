# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Builders::ClassDiagram do
  let(:direction) do
    described_class.new.apply(
      { direction: { dir_value: "LR" } }, ""
    )
  end
  let(:unknown) { described_class.new.apply({ unknown: true }, "") }
  let(:evidence) do
    [direction.direction, direction.entities,
     unknown.direction, unknown.entities]
  end

  it "accepts a standalone hash and ignores an unknown statement" do
    expect(evidence).to eq(["LR", [], nil, []])
  end
end
