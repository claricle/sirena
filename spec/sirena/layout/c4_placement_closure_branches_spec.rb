# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::C4Placement do
  let(:empty_boundary) do
    {
      width: 0, height: 0, children: [], header: 20,
      metadata: { boundary_type: "Boundary" }
    }
  end
  let(:graph) do
    { children: [empty_boundary, empty_boundary.dup], metadata: {} }
  end

  it "starts a boundary at the same x as an empty boundary beside it" do
    described_class.apply(graph)
    expect(graph[:children].map { |node| node[:x] }).to eq([150, 150])
  end
end
