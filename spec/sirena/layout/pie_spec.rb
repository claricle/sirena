# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/pie"

RSpec.describe Sirena::Layout::Pie do
  subject(:graph) { described_class.new.to_graph(diagram) }

  let(:diagram) { Sirena::Diagram::Pie.new }

  it "keeps an empty pie renderable" do
    expect(graph).to include(
      id: "pie",
      show_data: false,
      slices: [],
      metadata: { total_value: 0, slice_count: 0 },
    )
  end

  it "transforms populated slices and their proportions" do
    diagram.id = "share"
    diagram.title = "Market share"
    diagram.show_data = true
    diagram.acc_title = "Share by product"
    diagram.acc_description = "One quarter and three quarters"
    diagram.slices = [slice("Small", 1), slice("Large", 3)]

    expect(graph).to eq(
      id: "share",
      title: "Market share",
      show_data: true,
      acc_title: "Share by product",
      acc_description: "One quarter and three quarters",
      slices: expected_slices,
      metadata: { total_value: 4.0, slice_count: 2 },
    )
  end

  def slice(label, value)
    Sirena::Diagram::PieSlice.new(label: label, value: value)
  end

  def expected_slices
    [
      { id: "slice_0", label: "Small", value: 1.0, percentage: 25.0, angle: 90.0, index: 0 },
      { id: "slice_1", label: "Large", value: 3.0, percentage: 75.0, angle: 270.0, index: 1 },
    ]
  end
end
