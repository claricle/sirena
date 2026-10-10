# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::TreemapPlacement, ".call" do
  it "collapses a child that is narrower than its inset" do
    tiny = { value: 1, children: [] }
    root = { value: 101, children: [tiny, { value: 100, children: [] }] }

    described_class.call(root, 1000, 400)

    expect(tiny.values_at(:x0, :x1)).to eq([10, 10])
  end
end
