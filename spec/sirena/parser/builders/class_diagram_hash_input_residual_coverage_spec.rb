# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Builders::ClassDiagram do
  it "accepts a standalone hash and ignores an unknown statement" do
    direction = described_class.new.apply(
      { direction: { dir_value: "LR" } }, ""
    )
    unknown = described_class.new.apply({ unknown: true }, "")

    expect([direction.direction, direction.entities,
            unknown.direction, unknown.entities])
      .to eq(["LR", [], nil, []])
  end
end
