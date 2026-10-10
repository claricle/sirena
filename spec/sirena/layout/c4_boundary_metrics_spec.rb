# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::C4BoundaryMetrics do
  # 46 is the header mmdc leaves above the first box of c4/007: a 17 high
  # label at 8, then the type 5 below it and 16 high.
  it "reserves label and type height above the first box" do
    metrics = described_class.new(label: "global", type: "global")
    expect(metrics.height).to eq(46)
  end

  it "puts the type line 5 px under the label" do
    metrics = described_class.new(label: "x", type: "system")
    expect(metrics.type_offset).to eq(30)
  end

  it "reserves only the label height without a type" do
    expect(described_class.new(label: "x").height).to eq(25)
  end

  it "has no type offset without a type" do
    expect(described_class.new(label: "x").type_offset).to be_nil
  end
end
